# app/helpers/user_details_helper.rb
module UserDetailsHelper
  def status_badge_config(status)
    case status
    when "pending"
      { color: "bg-yellow-100 text-yellow-800", text: "Pending", icon: "fas fa-clock" }
    when "l1_approved"
      { color: "bg-green-100 text-green-800", text: "L1 Approved", icon: "fas fa-check-circle" }
    when "l1_returned"
      { color: "bg-red-100 text-red-800", text: "L1 Returned", icon: "fas fa-exclamation-triangle" }
    when "l2_approved"
      { color: "bg-emerald-100 text-emerald-800", text: "L2 Approved", icon: "fas fa-check-double" }
    when "l2_returned"
      { color: "bg-orange-100 text-orange-800", text: "L2 Returned", icon: "fas fa-exclamation-triangle" }
    when "submitted"
      { color: "bg-blue-100 text-blue-800", text: "Submitted", icon: "fas fa-paper-plane" }
    else
      { color: "bg-gray-100 text-gray-600", text: "No Status", icon: "fas fa-question-circle" }
    end
  end

  def achievement_percentage_class(percentage)
    if percentage >= 100
      "bg-green-100 text-green-800"
    elsif percentage >= 75
      "bg-blue-100 text-blue-800"
    elsif percentage >= 50
      "bg-yellow-100 text-yellow-800"
    else
      "bg-red-100 text-red-800"
    end
  end

  def quarter_background_class(quarter)
    case quarter
    when "Q1"
      "bg-blue-50"
    when "Q2"
      "bg-green-50"
    when "Q3"
      "bg-orange-50"
    when "Q4"
      "bg-purple-50"
    else
      "bg-gray-50"
    end
  end

  def format_achievement_value(value)
    return "-" if value.blank?

    # Format numbers with appropriate precision
    if value.is_a?(Numeric)
      value % 1 == 0 ? value.to_i.to_s : value.round(2).to_s
    else
      value.to_s
    end
  end

  def calculate_quarter_status(months, existing_achievements)
    achievements = months.map { |month| existing_achievements[month] }.compact
    calculate_overall_quarter_status_from_achievements(achievements)
  end

  def calculate_overall_quarter_status_from_achievements(achievements)
    achievements = Array(achievements).compact
    return "pending" if achievements.empty?

    statuses = achievements.map { |achievement| achievement.status.presence || "pending" }
    has_l1_review = quarter_review_present?(achievements, :l1)
    has_l2_review = quarter_review_present?(achievements, :l2)

    if statuses.include?("l2_returned")
      "l2_returned"
    elsif statuses.include?("l1_returned")
      "l1_returned"
    elsif statuses.include?("l2_approved") || has_l2_review
      "l2_approved"
    elsif statuses.include?("l1_approved") || has_l1_review
      "l1_approved"
    elsif statuses.include?("submitted")
      "submitted"
    else
      "pending"
    end
  end

  def quarter_summary(user_detail, months)
    existing_achievements = user_detail.achievements.index_by(&:month)

    targets = months.map { |month| user_detail.send(month.to_sym).to_f }.sum
    achievements = months.map { |month| existing_achievements[month]&.achievement.to_f || 0 }.sum
    percentage = targets > 0 ? ((achievements / targets) * 100).round(1) : 0

    {
      total_target: targets,
      total_achievement: achievements,
      percentage: percentage,
      status: calculate_quarter_status(months, existing_achievements)
    }
  end

  private

  def quarter_review_present?(achievements, level)
    achievements.any? do |achievement|
      remark = achievement.achievement_remark
      next false unless remark

      percentage = level == :l1 ? remark.l1_percentage : remark.l2_percentage
      review_remarks = level == :l1 ? remark.l1_remarks : remark.l2_remarks

      percentage.present? || review_remarks.present?
    end
  end
end
