require "axlsx"

class HomeController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_l1_pulse_access!, only: [ :l1_pulse_360, :save_l1_pulse_360 ]
  helper_method :composite_category_details, :pulse_category_details, :score_rating_details, :score_rating_text

  def index
  end

  def dashboard
    if admin_dashboard_user?
      load_admin_dashboard
    else
      load_employee_dashboard
    end
  end

  def l1_pulse_360
    @dashboard_mode = :l1_pulse
    load_l1_pulse_rows
  end

  def export_dashboard_xlsx
    if admin_dashboard_user?
      load_admin_dashboard
    else
      load_employee_dashboard
    end

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Annual Review") do |sheet|
      if @dashboard_mode == :admin
        sheet.add_row [ "Employee", "Code", "Department", "Q1", "Q2", "Q3", "Q4", "Annual %" ]
        @employee_rows.each do |row|
          sheet.add_row [
            row[:employee_name], row[:employee_code], row[:department],
            formatted_percent(row[:quarter_summaries][0][:percentage]), formatted_percent(row[:quarter_summaries][1][:percentage]),
            formatted_percent(row[:quarter_summaries][2][:percentage]), formatted_percent(row[:quarter_summaries][3][:percentage]),
            formatted_percent(row[:annual_percentage])
          ]
        end
      else
        sheet.add_row [ "Quarter", "KRA Score" ]
        @quarter_summaries.each do |quarter|
          sheet.add_row [ quarter[:name], formatted_percent(quarter[:percentage]) ]
        end
        sheet.add_row [ "Annual Average", formatted_percent(@annual_percentage) ]
      end
    end

    workbook.add_worksheet(name: "Score Range") do |sheet|
      sheet.add_row [ "Score Range", "Band", "Rating", "Recommended Action" ]
      score_range_rows.each do |row|
        sheet.add_row [ row[:score_range], row[:band], row[:rating], row[:action] ]
      end
    end

    workbook.add_worksheet(name: @dashboard_mode == :admin ? "Pulse 360 Score" : "Pulse Check") do |sheet|
      if @dashboard_mode == :admin
        sheet.add_row [
          "Staff Name", "Role", "Wt %", "Sense of Purpose & Mission Alignment (1-5)", "Workload & Well-being Balance (1-5)",
          "Manager Effectiveness & Support (1-5)", "Team Collaboration & Relationships (1-5)", "Recognition & Growth Opportunities (1-5)",
          "Org. Communication & Transparency (1-5)", "Learning & Development Access (1-5)", "Role Clarity & Goal Setting (1-5)",
          "Work Environment & Safety (1-5)", "Commitment & Retention Intent (1-5)", "Total /50", "Category & Action"
        ]
        @employee_rows.each do |row|
          category = row[:pulse_category]
          sheet.add_row [
            row[:employee_name], row[:role], row[:summary_scores][:pulse_score],
            row[:pulse_scores][:sense_of_purpose], row[:pulse_scores][:workload_balance],
            row[:pulse_scores][:manager_effectiveness], row[:pulse_scores][:team_collaboration],
            row[:pulse_scores][:recognition_growth], row[:pulse_scores][:org_communication],
            row[:pulse_scores][:learning_development], row[:pulse_scores][:role_clarity],
            row[:pulse_scores][:work_environment], row[:pulse_scores][:commitment_retention],
            row[:pulse_scores][:total_score],
            category.present? ? "#{category[:category]} - #{category[:action]}" : ""
          ]
        end
        if @employee_rows.any?
          avg_total = (@employee_rows.sum { |r| r[:pulse_scores][:total_score].to_f } / @employee_rows.size).round(0).to_i
          avg_category = pulse_category_details(avg_total)
          sheet.add_row [
            "TEAM AVERAGE", "",
            (@employee_rows.sum { |r| r[:summary_scores][:pulse_score].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:sense_of_purpose].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:workload_balance].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:manager_effectiveness].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:team_collaboration].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:recognition_growth].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:org_communication].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:learning_development].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:role_clarity].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:work_environment].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:commitment_retention].to_f } / @employee_rows.size).round(1),
            (@employee_rows.sum { |r| r[:pulse_scores][:total_score].to_f } / @employee_rows.size).round(1),
            "#{avg_category[:category]} - #{avg_category[:action]}"
          ]
        end
      else
        sheet.add_row [ "Pulse Dimension", "Wt %", "Score (1-5)", "Wtd Score", "Rating" ]
        pulse_dimension_rows_for(@dashboard_pulse_scores).each do |dimension|
          sheet.add_row [
            dimension[:label], "#{dimension[:weight]}%", dimension[:score],
            dimension[:weighted_score].present? ? "#{dimension[:weighted_score]}%" : "-",
            dimension[:rating_text]
          ]
        end
        pulse_raw = pulse_raw_percentage(@dashboard_pulse_scores[:total_score])
        sheet.add_row [ "PULSE TOTAL", "100%", "", pulse_raw.present? ? "Pulse Raw -> #{pulse_raw}%" : "Pending assessment", @dashboard_pulse_category&.dig(:category) || "Pending" ]
      end
    end

    workbook.add_worksheet(name: "Line Manager Feedback") do |sheet|
      if @dashboard_mode == :admin
        sheet.add_row [ "Employee", "Code", "Professionalism & Conduct (1-5)", "Quality & Accuracy of Work Output (1-5)", "Initiative & Problem-Solving (1-5)", "Adherence to PAPL Values & Culture (1-5)", "Cross-functional Collaboration (1-5)", "Time Management & Reliability (1-5)", "Growth Mindset & Development (1-5)", "Mgr Score /10", "Manager Remarks" ]
        @employee_rows.each do |row|
          criteria = row[:manager_feedback][:criteria]
          sheet.add_row [
            row[:employee_name], row[:employee_code],
            criteria[0][:score], criteria[1][:score], criteria[2][:score], criteria[3][:score],
            criteria[4][:score], criteria[5][:score], criteria[6][:score],
            row[:pulse_assessment_score], row[:pulse_assessment_remarks]
          ]
        end
      else
        sheet.add_row [ "Assessment Criteria", "Wt %", "Score (1-5)", "Wtd Score", "Rating" ]
        Array(@dashboard_manager_feedback[:criteria]).each do |criterion|
          sheet.add_row [
            criterion[:label], "#{criterion[:weight]}%", criterion[:score],
            criterion[:weighted_score].present? ? "#{criterion[:weighted_score]}%" : "-",
            score_rating_text(criterion[:score])
          ]
        end
        sheet.add_row [ "MANAGER TOTAL", "100%", "", @dashboard_manager_feedback[:available] ? "Mgr Raw -> #{@dashboard_manager_feedback[:raw_total]}%" : "Pending assessment", @dashboard_pulse_remark_score.present? ? "Score #{@dashboard_pulse_remark_score}/10" : "Pending" ]
        sheet.add_row []
        sheet.add_row [ "Manager Remarks", @dashboard_pulse_remarks.presence || "No manager remarks available yet." ]
      end
    end

    workbook.add_worksheet(name: "Composite Score") do |sheet|
      if @dashboard_mode == :admin
        sheet.add_row [ "User", "KRA %", "Pulse %", "Manager %", "Final Total" ]
        @employee_rows.each do |row|
          sheet.add_row [
            row[:employee_name], formatted_percent(row[:annual_percentage]), formatted_percent(row[:pulse_raw_percentage]),
            formatted_percent(row[:manager_raw_percentage]),
            formatted_percent(row[:summary_scores][:final_total])
          ]
        end
        if @employee_rows.any?
          sheet.add_row [
            "TEAM AVERAGE",
            formatted_percent((@employee_rows.sum { |r| r[:annual_percentage].to_f } / @employee_rows.size)),
            formatted_percent((@employee_rows.sum { |r| r[:pulse_raw_percentage].to_f } / @employee_rows.size)),
            formatted_percent((@employee_rows.sum { |r| r[:manager_raw_percentage].to_f } / @employee_rows.size)),
            formatted_percent((@employee_rows.sum { |r| r[:summary_scores][:final_total].to_f } / @employee_rows.size))
          ]
        end
      else
        sheet.add_row [ "Section", "Raw Score", "Section Weight", "Weighted Contribution" ]
        employee_summary_rows.each do |row|
          sheet.add_row row
        end
        composite = composite_category_details(@dashboard_summary_scores[:final_total])
        sheet.add_row []
        sheet.add_row [ "Final Composite Score", "#{@dashboard_summary_scores[:final_total]}%", composite[:band], "Rating #{composite[:rating]} / 5" ]
      end
    end

    tempfile = Tempfile.new([ "dashboard_export", ".xlsx" ])
    package.serialize(tempfile.path)
    send_file tempfile.path, filename: "dashboard_export_#{Date.current}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def export_dashboard_section_xlsx
    if admin_dashboard_user?
      load_admin_dashboard
    else
      load_employee_dashboard
    end

    package = Axlsx::Package.new
    workbook = package.workbook
    case params[:section]
    when "annual"
      workbook.add_worksheet(name: "Annual Review") do |sheet|
        if @dashboard_mode == :admin
          sheet.add_row [ "Employee", "Code", "Department", "Q1", "Q2", "Q3", "Q4", "Annual %" ]
          @employee_rows.each do |row|
            sheet.add_row [ row[:employee_name], row[:employee_code], row[:department], formatted_percent(row[:quarter_summaries][0][:percentage]), formatted_percent(row[:quarter_summaries][1][:percentage]), formatted_percent(row[:quarter_summaries][2][:percentage]), formatted_percent(row[:quarter_summaries][3][:percentage]), formatted_percent(row[:annual_percentage]) ]
          end
        else
          sheet.add_row [ "Quarter", "KRA Score" ]
          @quarter_summaries.each do |quarter|
            sheet.add_row [ quarter[:name], formatted_percent(quarter[:percentage]) ]
          end
          sheet.add_row [ "Annual Average", formatted_percent(@annual_percentage) ]
        end
      end
    when "pulse"
      workbook.add_worksheet(name: "Pulse Score") do |sheet|
        if @dashboard_mode == :admin
          sheet.add_row [ "Staff Name", "Role", "Wt %", "Sense of Purpose & Mission Alignment (1-5)", "Workload & Well-being Balance (1-5)", "Manager Effectiveness & Support (1-5)", "Team Collaboration & Relationships (1-5)", "Recognition & Growth Opportunities (1-5)", "Org. Communication & Transparency (1-5)", "Learning & Development Access (1-5)", "Role Clarity & Goal Setting (1-5)", "Work Environment & Safety (1-5)", "Commitment & Retention Intent (1-5)", "Total /50", "Category & Action" ]
          @employee_rows.each do |row|
            category = row[:pulse_category]
            sheet.add_row [ row[:employee_name], row[:role], row[:summary_scores][:pulse_score], row[:pulse_scores][:sense_of_purpose], row[:pulse_scores][:workload_balance], row[:pulse_scores][:manager_effectiveness], row[:pulse_scores][:team_collaboration], row[:pulse_scores][:recognition_growth], row[:pulse_scores][:org_communication], row[:pulse_scores][:learning_development], row[:pulse_scores][:role_clarity], row[:pulse_scores][:work_environment], row[:pulse_scores][:commitment_retention], row[:pulse_scores][:total_score], category.present? ? "#{category[:category]} - #{category[:action]}" : "" ]
          end
          if @employee_rows.any?
            avg_total = (@employee_rows.sum { |r| r[:pulse_scores][:total_score].to_f } / @employee_rows.size).round(0).to_i
            avg_category = pulse_category_details(avg_total)
            sheet.add_row [ "TEAM AVERAGE", "", (@employee_rows.sum { |r| r[:summary_scores][:pulse_score].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:sense_of_purpose].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:workload_balance].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:manager_effectiveness].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:team_collaboration].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:recognition_growth].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:org_communication].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:learning_development].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:role_clarity].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:work_environment].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:commitment_retention].to_f } / @employee_rows.size).round(1), (@employee_rows.sum { |r| r[:pulse_scores][:total_score].to_f } / @employee_rows.size).round(1), "#{avg_category[:category]} - #{avg_category[:action]}" ]
          end
        else
          sheet.add_row [ "Pulse Dimension", "Wt %", "Score (1-5)", "Wtd Score", "Rating" ]
          pulse_dimension_rows_for(@dashboard_pulse_scores).each do |dimension|
            sheet.add_row [ dimension[:label], "#{dimension[:weight]}%", dimension[:score], dimension[:weighted_score].present? ? "#{dimension[:weighted_score]}%" : "-", dimension[:rating_text] ]
          end
          pulse_raw = pulse_raw_percentage(@dashboard_pulse_scores[:total_score])
          sheet.add_row [ "PULSE TOTAL", "100%", "", pulse_raw.present? ? "Pulse Raw -> #{pulse_raw}%" : "Pending assessment", @dashboard_pulse_category&.dig(:category) || "Pending" ]
        end
      end
    when "remarks"
      workbook.add_worksheet(name: "Line Manager Feedback") do |sheet|
        if @dashboard_mode == :admin
          sheet.add_row [ "Employee", "Code", "Professionalism & Conduct (1-5)", "Quality & Accuracy of Work Output (1-5)", "Initiative & Problem-Solving (1-5)", "Adherence to PAPL Values & Culture (1-5)", "Cross-functional Collaboration (1-5)", "Time Management & Reliability (1-5)", "Growth Mindset & Development (1-5)", "Mgr Score /10", "Manager Remarks" ]
          @employee_rows.each do |row|
            criteria = row[:manager_feedback][:criteria]
            sheet.add_row [
              row[:employee_name], row[:employee_code],
              criteria[0][:score], criteria[1][:score], criteria[2][:score], criteria[3][:score],
              criteria[4][:score], criteria[5][:score], criteria[6][:score],
              row[:pulse_assessment_score], row[:pulse_assessment_remarks]
            ]
          end
        else
          sheet.add_row [ "Assessment Criteria", "Wt %", "Score (1-5)", "Wtd Score", "Rating" ]
          Array(@dashboard_manager_feedback[:criteria]).each do |criterion|
            sheet.add_row [ criterion[:label], "#{criterion[:weight]}%", criterion[:score], criterion[:weighted_score].present? ? "#{criterion[:weighted_score]}%" : "-", score_rating_text(criterion[:score]) ]
          end
          sheet.add_row [ "MANAGER TOTAL", "100%", "", @dashboard_manager_feedback[:available] ? "Mgr Raw -> #{@dashboard_manager_feedback[:raw_total]}%" : "Pending assessment", @dashboard_pulse_remark_score.present? ? "Score #{@dashboard_pulse_remark_score}/10" : "Pending" ]
          sheet.add_row []
          sheet.add_row [ "Manager Remarks", @dashboard_pulse_remarks.presence || "No manager remarks available yet." ]
        end
      end
    when "summary"
      workbook.add_worksheet(name: "Composite Score") do |sheet|
        if @dashboard_mode == :admin
          sheet.add_row [ "User", "KRA %", "Pulse %", "Manager %", "Final Total" ]
          @employee_rows.each do |row|
            sheet.add_row [ row[:employee_name], formatted_percent(row[:annual_percentage]), formatted_percent(row[:pulse_raw_percentage]), formatted_percent(row[:manager_raw_percentage]), formatted_percent(row[:summary_scores][:final_total]) ]
          end
          if @employee_rows.any?
            sheet.add_row [ "TEAM AVERAGE", formatted_percent((@employee_rows.sum { |r| r[:annual_percentage].to_f } / @employee_rows.size)), formatted_percent((@employee_rows.sum { |r| r[:pulse_raw_percentage].to_f } / @employee_rows.size)), formatted_percent((@employee_rows.sum { |r| r[:manager_raw_percentage].to_f } / @employee_rows.size)), formatted_percent((@employee_rows.sum { |r| r[:summary_scores][:final_total].to_f } / @employee_rows.size)) ]
          end
        else
          sheet.add_row [ "Section", "Raw Score", "Section Weight", "Weighted Contribution" ]
          employee_summary_rows.each do |row|
            sheet.add_row row
          end
          composite = composite_category_details(@dashboard_summary_scores[:final_total])
          sheet.add_row []
          sheet.add_row [ "Final Composite Score", "#{@dashboard_summary_scores[:final_total]}%", composite[:band], "Rating #{composite[:rating]} / 5" ]
        end
      end
    end
    tempfile = Tempfile.new([ "dashboard_#{params[:section]}", ".xlsx" ])
    package.serialize(tempfile.path)
    send_file tempfile.path, filename: "dashboard_#{params[:section]}_#{Date.current}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def save_l1_pulse_360
    submitted_rows = params[:pulse_assessments] || {}
    employee_details = l1_managed_employee_details.index_by { |employee_detail| employee_detail.id.to_s }

    submitted_rows.each do |employee_detail_id, assessment_params|
      employee_detail = employee_details[employee_detail_id]
      next unless employee_detail
      next if assessment_blank?(assessment_params)

      assessment = L1PulseAssessment.find_or_initialize_by(employee_detail_id: employee_detail.id, l1_user_id: current_user.id)
      assessment.assign_attributes(
        sense_of_purpose: assessment_params[:sense_of_purpose].presence, workload_balance: assessment_params[:workload_balance].presence,
        manager_effectiveness: assessment_params[:manager_effectiveness].presence, team_collaboration: assessment_params[:team_collaboration].presence,
        recognition_growth: assessment_params[:recognition_growth].presence, org_communication: assessment_params[:org_communication].presence,
        learning_development: assessment_params[:learning_development].presence, role_clarity: assessment_params[:role_clarity].presence,
        work_environment: assessment_params[:work_environment].presence, commitment_retention: assessment_params[:commitment_retention].presence,
        remarks: assessment_params[:remarks].presence, professionalism_conduct: assessment_params[:professionalism_conduct].presence,
        work_quality_accuracy: assessment_params[:work_quality_accuracy].presence, initiative_problem_solving: assessment_params[:initiative_problem_solving].presence,
        papl_values_culture: assessment_params[:papl_values_culture].presence, collaboration: assessment_params[:collaboration].presence,
        time_management_reliability: assessment_params[:time_management_reliability].presence, growth_mindset_development: assessment_params[:growth_mindset_development].presence
      )
      manager_feedback = manager_feedback_summary_for(assessment)
      assessment.remark_score = manager_feedback[:score_on_ten]
      assessment.save!
    end

    redirect_to l1_pulse_360_path, notice: "Scores saved successfully."
  rescue ActiveRecord::RecordInvalid => e
    @dashboard_mode = :l1_pulse
    @pulse_error_message = e.record.errors.full_messages.to_sentence
    load_l1_pulse_rows
    render :l1_pulse_360, status: :unprocessable_entity
  end

  private

  def admin_dashboard_user?
    current_user.hod? || current_user.admin?
  end

  def quarter_map
    { "Q1" => %w[april may june], "Q2" => %w[july august september], "Q3" => %w[october november december], "Q4" => %w[january february march] }
  end

  def quarter_summaries_for(user_details)
    quarter_map.map do |name, months|
      quarter_achievements = user_details.flat_map do |detail|
        detail.achievements.select do |achievement|
          months.include?(achievement.month.to_s.downcase) && achievement.achievement_remark.present?
        end
      end

      l1_percentages = quarter_achievements.filter_map { |achievement| achievement.achievement_remark&.l1_percentage&.to_f }
      l1_rems = quarter_achievements.filter_map { |achievement| achievement.achievement_remark&.l1_remarks }.uniq.compact

      {
        name: name,
        percentage: l1_percentages.any? ? (l1_percentages.sum / l1_percentages.size).round(1) : 0.0,
        l1_remarks: l1_rems,
        remarks: l1_rems
      }
    end
  end

  def pulse_category_details(ts)
    case ts
    when 45..50 then { stars: "★★★★★", category: "Outstanding", action: "Accelerated growth track / highest increment", className: "stars-5" }
    when 38..44 then { stars: "★★★★", category: "Exceeds Expectations", action: "Merit increment + recognition award", className: "stars-4" }
    when 30..37 then { stars: "★★★", category: "Meets Expectations", action: "Standard increment as per policy", className: "stars-3" }
    when 23..29 then { stars: "★★", category: "Needs Improvement", action: "PIP + structured coaching plan", className: "stars-2" }
    else { stars: "★", category: "Unsatisfactory", action: "Formal PIP / disciplinary review", className: "stars-1" }
    end
  end

  def score_rating_details(score)
    return nil if score.blank?

    case score.to_i
    when 5 then { rating: 5, stars: "★★★★★", className: "stars-5", band: "Outstanding" }
    when 4 then { rating: 4, stars: "★★★★", className: "stars-4", band: "Exceeds Expectations" }
    when 3 then { rating: 3, stars: "★★★", className: "stars-3", band: "Meets Expectations" }
    when 2 then { rating: 2, stars: "★★", className: "stars-2", band: "Needs Improvement" }
    else { rating: 1, stars: "★", className: "stars-1", band: "Unsatisfactory" }
    end
  end

  def score_rating_text(score)
    details = score_rating_details(score)
    details ? "#{details[:rating]} (#{details[:stars]})" : "-"
  end

  def score_range_rows
    [
      { score_range: ">= 90%", band: "Outstanding", rating: "5 (★★★★★)", action: "Accelerated growth track / highest increment" },
      { score_range: "75 - 89%", band: "Exceeds Expectations", rating: "4 (★★★★)", action: "Merit increment + recognition award" },
      { score_range: "60 - 74%", band: "Meets Expectations", rating: "3 (★★★)", action: "Standard increment as per policy" },
      { score_range: "45 - 59%", band: "Needs Improvement", rating: "2 (★★)", action: "PIP + structured coaching plan" },
      { score_range: "< 45%", band: "Unsatisfactory", rating: "1 (★)", action: "Formal PIP / disciplinary review" }
    ]
  end

  def pulse_raw_percentage(total_score)
    return nil if total_score.blank?

    ((total_score.to_f / 50.0) * 100.0).round(2)
  end

  def pulse_dimension_rows_for(pulse_scores)
    [
      { label: "Sense of Purpose & Mission Alignment", weight: 10, score: pulse_scores&.dig(:sense_of_purpose) },
      { label: "Workload & Well-being Balance", weight: 10, score: pulse_scores&.dig(:workload_balance) },
      { label: "Manager Effectiveness & Support", weight: 10, score: pulse_scores&.dig(:manager_effectiveness) },
      { label: "Team Collaboration & Relationships", weight: 10, score: pulse_scores&.dig(:team_collaboration) },
      { label: "Recognition & Growth Opportunities", weight: 10, score: pulse_scores&.dig(:recognition_growth) },
      { label: "Org. Communication & Transparency", weight: 10, score: pulse_scores&.dig(:org_communication) },
      { label: "Learning & Development Access", weight: 10, score: pulse_scores&.dig(:learning_development) },
      { label: "Role Clarity & Goal Setting", weight: 10, score: pulse_scores&.dig(:role_clarity) },
      { label: "Work Environment & Safety", weight: 10, score: pulse_scores&.dig(:work_environment) },
      { label: "Commitment & Retention Intent", weight: 10, score: pulse_scores&.dig(:commitment_retention) }
    ].map do |dimension|
      score = dimension[:score]
      weighted_score = score.present? ? ((score.to_f / 5.0) * dimension[:weight]).round(2) : nil

      dimension.merge(weighted_score: weighted_score, rating_text: score_rating_text(score))
    end
  end

  def employee_summary_rows
    pulse_raw = pulse_raw_percentage(@dashboard_pulse_scores[:total_score])

    [
      [ "A - KRA", @annual_percentage.present? ? "#{@annual_percentage}%" : "-", "75%", @dashboard_summary_scores[:annual_score].present? ? "#{@dashboard_summary_scores[:annual_score]}%" : "-" ],
      [ "B - Pulse Check", pulse_raw.present? ? "#{pulse_raw}%" : "Pending", "15%", @dashboard_summary_scores[:pulse_score].present? ? "#{@dashboard_summary_scores[:pulse_score]}%" : "-" ],
      [ "C - Manager Feedback", @dashboard_manager_feedback[:available] ? "#{@dashboard_manager_feedback[:raw_total]}%" : "Pending", "10%", @dashboard_summary_scores[:remarks_score].present? ? "#{@dashboard_summary_scores[:remarks_score]}%" : "-" ]
    ]
  end

  def manager_feedback_raw_percentage(a)
    return 0.0 if a.blank? || assessment_blank?(a)
    w = { professionalism_conduct: 15, work_quality_accuracy: 15, initiative_problem_solving: 15, papl_values_culture: 15, collaboration: 15, time_management_reliability: 15, growth_mindset_development: 10 }
    val = w.sum { |f, v| (a.send(f).to_f / 5.0) * v }
    (val * 0.10).round(2)
  end

  def manager_feedback_criteria_for(assessment)
    [
      { key: :professionalism_conduct, label: "Professionalism & Conduct", weight: 15 },
      { key: :work_quality_accuracy, label: "Quality & Accuracy of Work Output", weight: 15 },
      { key: :initiative_problem_solving, label: "Initiative & Problem-Solving", weight: 15 },
      { key: :papl_values_culture, label: "Adherence to PAPL Values & Culture", weight: 15 },
      { key: :collaboration, label: "Cross-functional Collaboration", weight: 15 },
      { key: :time_management_reliability, label: "Time Management & Reliability", weight: 15 },
      { key: :growth_mindset_development, label: "Growth Mindset & Development", weight: 10 }
    ].map do |criterion|
      score = assessment&.public_send(criterion[:key])
      weighted_score = score.present? ? ((score.to_f / 5.0) * criterion[:weight]).round(2) : nil

      criterion.merge(score: score, weighted_score: weighted_score)
    end
  end

  def manager_feedback_summary_for(assessment)
    criteria = manager_feedback_criteria_for(assessment)
    raw_total = criteria.sum { |criterion| criterion[:weighted_score].to_f }.round(2)
    has_scores = criteria.any? { |criterion| criterion[:score].present? }
    score_on_ten = has_scores ? (raw_total / 10.0).round(1) : nil

    {
      criteria: criteria,
      raw_total: raw_total,
      score_on_ten: score_on_ten,
      weighted_score: score_on_ten.present? ? ((score_on_ten / 10.0) * 10.0).round(2) : nil,
      available: has_scores
    }
  end

  def weighted_summary_scores(annual_percentage:, pulse_total_score:, remark_score:)
    ap = annual_percentage.to_f
    ps = pulse_total_score.present? ? pulse_total_score.to_f : 0.0
    rs = remark_score.present? ? remark_score.to_f : 0.0
    ws_annual = (ap * 0.75).round(2)
    ws_pulse = ((ps.to_f / 50.0) * 15.0).round(2)
    ws_remarks = ((rs.to_f / 10.0) * 10.0).round(2)
    { annual_score: ws_annual, pulse_score: ws_pulse, remarks_score: ws_remarks, final_total: (ws_annual + ws_pulse + ws_remarks).round(2) }
  end

  def pulse_scores_from_assessment(a)
    { sense_of_purpose: a.sense_of_purpose.to_i, workload_balance: a.workload_balance.to_i, manager_effectiveness: a.manager_effectiveness.to_i, team_collaboration: a.team_collaboration.to_i, recognition_growth: a.recognition_growth.to_i, org_communication: a.org_communication.to_i, learning_development: a.learning_development.to_i, role_clarity: a.role_clarity.to_i, work_environment: a.work_environment.to_i, commitment_retention: a.commitment_retention.to_i, total_score: pulse_total_for_assessment(a) }
  end

  def blank_pulse_scores
    { sense_of_purpose: nil, workload_balance: nil, manager_effectiveness: nil, team_collaboration: nil, recognition_growth: nil, org_communication: nil, learning_development: nil, role_clarity: nil, work_environment: nil, commitment_retention: nil, total_score: nil }
  end

  def composite_category_details(ft)
    case ft
    when 90..100 then { band: "Outstanding", rating: 5, stars: "★★★★★", className: "stars-5", action: "Accelerated growth track" }
    when 75..89 then { band: "Exceeds Expectations", rating: 4, stars: "★★★★", className: "stars-4", action: "Merit increment" }
    when 60..74 then { band: "Meets Expectations", rating: 3, stars: "★★★", className: "stars-3", action: "Standard increment" }
    when 45..59 then { band: "Needs Improvement", rating: 2, stars: "★★", className: "stars-2", action: "PIP" }
    else { band: "Unsatisfactory", rating: 1, stars: "★", className: "stars-1", action: "Formal PIP" }
    end
  end

  def assessment_blank?(p)
    [ :sense_of_purpose, :workload_balance, :manager_effectiveness, :team_collaboration, :recognition_growth, :org_communication, :learning_development, :role_clarity, :work_environment, :commitment_retention, :remarks, :professionalism_conduct, :work_quality_accuracy, :initiative_problem_solving, :papl_values_culture, :collaboration, :time_management_reliability, :growth_mindset_development ].all? { |f| p[f].blank? }
  end

  def build_employee_dashboard_row(ed)
    ud = user_details_for_selected_financial_year(ed.user_details)
    qs = quarter_summaries_for(ud)
    ap = (qs.sum { |q| q[:percentage] } / 4.0).round(1)
    pa = ed.l1_pulse_assessments.max_by(&:updated_at)
    ps = pa ? pulse_scores_from_assessment(pa) : blank_pulse_scores
    manager_feedback = manager_feedback_summary_for(pa)
    ts = ps[:total_score]
    ws_pulse = ((ts.to_f / 50.0) * 15.0).round(2)
    ws_pulse = 0.0 if pa.blank? || assessment_blank?(pa)
    {
      employee_detail_id: ed.id, employee_name: ed.employee_name || "N/A", employee_code: ed.employee_code || "N/A",
      role: ed.post.presence || "Employee",
      department: ud.first&.department&.department_type || ed.department || "N/A",
      quarter_summaries: qs, annual_percentage: ap,
      total: qs.sum { |q| q[:percentage] }.round(1),
      l1_remarks: qs.flat_map { |q| q[:l1_remarks] }.uniq,
      remarks: qs.flat_map { |q| q[:l1_remarks] }.uniq,
      pulse_scores: ps, pulse_available: pa.present?, pulse_weighted: ws_pulse,
      pulse_raw_percentage: pulse_raw_percentage(ts) || 0.0,
      pulse_category: pa ? pulse_category_details(ts) : nil,
      pulse_assessment_remarks: pa&.remarks, pulse_assessment_score: manager_feedback[:score_on_ten] || pa&.remark_score,
      manager_feedback: manager_feedback,
      manager_feedback_raw: pa ? manager_feedback_raw_percentage(pa) : 0.0,
      manager_raw_percentage: manager_feedback[:raw_total].to_f,
      summary_scores: weighted_summary_scores(annual_percentage: ap, pulse_total_score: ts, remark_score: manager_feedback[:score_on_ten] || pa&.remark_score)
    }
  end

  def l1_assessment_for(ed)
    ed.l1_pulse_assessments.find { |a| a.l1_user_id == current_user.id } || ed.l1_pulse_assessments.build(l1_user_id: current_user.id)
  end

  def pulse_total_for_assessment(a)
    [ a.sense_of_purpose, a.workload_balance, a.manager_effectiveness, a.team_collaboration, a.recognition_growth, a.org_communication, a.learning_development, a.role_clarity, a.work_environment, a.commitment_retention ].compact.sum
  end

  def build_l1_pulse_row(ed)
    a = l1_assessment_for(ed)
    ts = pulse_total_for_assessment(a)
    ws_pulse = ((ts.to_f / 50.0) * 15.0).round(2)
    ws_pulse = 0.0 if a.blank? || assessment_blank?(a)
    selected_user_details = user_details_for_selected_financial_year(ed.user_details)
    { employee_detail_id: ed.id, employee_name: ed.employee_name, employee_code: ed.employee_code, department: selected_user_details.first&.department&.department_type || ed.department, assessment: a, total_score: ts, pulse_weighted: ws_pulse, pulse_category: pulse_category_details(ts), manager_feedback_raw: manager_feedback_raw_percentage(a) }
  end

  def formatted_percent(value)
    "#{format('%.2f', value.to_f)}%"
  end

  def load_l1_pulse_rows
    @pulse_rows = l1_managed_employee_details.map { |ed| build_l1_pulse_row(ed) }
  end

  def l1_managed_employee_details
    EmployeeDetail.includes(:l1_pulse_assessments, user_details: [ :department, achievements: :achievement_remark ]).order(:employee_name).then { |s| (current_user.hod? || current_user.admin?) ? s : s.where("l1_code = :c OR l1_employer_name = :e", c: current_user.employee_code, e: current_user.email) }
  end

  def ensure_l1_pulse_access!
    unless current_user.hod? || current_user.admin? || EmployeeDetail.exists?(l1_code: current_user.employee_code) || EmployeeDetail.exists?(l1_employer_name: current_user.email)
      redirect_to dashboard_path, alert: "Denied."
    end
  end

  def load_admin_dashboard
    @dashboard_mode = :admin
    @employee_rows = EmployeeDetail.includes(:l1_pulse_assessments, user_details: [ :department, achievements: :achievement_remark ]).order(:employee_name).map { |ed| build_employee_dashboard_row(ed) }
  end

  def load_employee_dashboard
    @dashboard_mode = :employee
    @employee_detail = current_user.employee_detail || EmployeeDetail.find_by(employee_email: current_user.email)
    @user_details = @employee_detail ? UserDetail.includes(:department, achievements: :achievement_remark).where(employee_detail_id: @employee_detail.id, financial_year: selected_financial_year) : UserDetail.none
    qs = quarter_summaries_for(@user_details)
    ap = (qs.sum { |q| q[:percentage] } / 4.0).round(1)
    pa = @employee_detail&.l1_pulse_assessments&.max_by(&:updated_at)
    ps = pa ? pulse_scores_from_assessment(pa) : blank_pulse_scores
    manager_feedback = manager_feedback_summary_for(pa)

    @quarter_summaries = qs
    @annual_total = qs.sum { |q| q[:percentage] }.round(1)
    @annual_percentage = ap
    @dashboard_employee_department = @user_details.first&.department&.department_type || @employee_detail&.department || "N/A"
    @dashboard_pulse_scores = ps
    @dashboard_pulse_category = pa ? pulse_category_details(ps[:total_score]) : nil
    @dashboard_pulse_available = pa.present?
    @dashboard_pulse_remarks = pa&.remarks
    @dashboard_pulse_remark_score = manager_feedback[:score_on_ten] || pa&.remark_score
    @dashboard_manager_feedback = manager_feedback
    @annual_l1_remarks = qs.flat_map { |q| q[:l1_remarks] }.uniq
    @annual_remarks = qs.flat_map { |q| q[:l1_remarks] }.uniq
    @dashboard_summary_scores = weighted_summary_scores(annual_percentage: ap, pulse_total_score: ps[:total_score], remark_score: @dashboard_pulse_remark_score)
  end

  def user_details_for_selected_financial_year(user_details)
    if user_details.respond_to?(:loaded?) && user_details.loaded?
      user_details.select { |detail| detail.financial_year == selected_financial_year }
    elsif user_details.respond_to?(:where)
      user_details.where(financial_year: selected_financial_year)
    else
      Array(user_details).select { |detail| detail.financial_year == selected_financial_year }
    end
  end
end
