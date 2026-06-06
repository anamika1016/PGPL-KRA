module ApplicationHelper
  def current_user_detail
    current_user&.user_detail
  end

  def user_display_name(user)
    return "N/A" if user.blank?

    user.display_name
  end

  def help_desk_user_action_count
    return 0 if current_user.blank?

    HelpDeskTicket.pending_user_action_for(current_user).count
  end

  def help_desk_assigned_count
    return 0 if current_user.blank? || !helpdesk_reviewer?

    HelpDeskTicket.open_for_review.assigned_to(current_user).count
  end

  def help_desk_notification_label(count)
    count.to_i > 99 ? "99+" : count.to_i.to_s
  end

  def asset_to_base64(asset_name)
    path = Rails.root.join("app", "assets", "images", asset_name)
    if File.exist?(path)
      content = File.binread(path)
      ext = File.extname(asset_name).downcase.delete(".")
      mime_type = case ext
      when "jpg", "jpeg" then "image/jpeg"
      when "png" then "image/png"
      else "image/#{ext}"
      end
      "data:#{mime_type};base64,#{Base64.strict_encode64(content)}"
    else
      Rails.logger.error "ASSET NOT FOUND: #{path}"
      ""
    end
  end
end
