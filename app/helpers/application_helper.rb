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

  def help_desk_format_text(text)
    simple_format(h(text.to_s.presence || "No details provided."))
  end

  def help_desk_support_update_text(ticket, support_update)
    message = support_update.message.to_s.strip
    return message if message.match?(/\AForwarded from\b/i)
    return message unless message.match?(/\bforward\b/i)

    department_name = ticket&.department&.department_type.presence || "current department"
    "Forwarded to #{department_name}: #{message}"
  end

  def help_desk_status_label(ticket)
    return "Unknown" if ticket.blank?
    return "Overdue" if ticket.respond_to?(:overdue_for_response?) && ticket.overdue_for_response?

    case ticket.status.to_s
    when "submitted"
      "Submitted"
    when "in_review"
      "In Review"
    when "reopened"
      "Reopened"
    when "resolved"
      ticket.respond_to?(:final_action_mode_label) ? "Awaiting #{ticket.final_action_mode_label}" : "Awaiting User Action"
    when "closed"
      if ticket.respond_to?(:closed_automatically?) && ticket.closed_automatically?
        ticket.respond_to?(:final_action_mode_approve_reject?) && ticket.final_action_mode_approve_reject? ? "Auto Approved" : "Auto Closed"
      else
        "Closed"
      end
    else
      ticket.status.to_s.humanize
    end
  end

  def help_desk_status_badge_tone(ticket)
    return "helpdesk-badge--neutral" if ticket.blank?
    return "helpdesk-badge--danger" if ticket.respond_to?(:overdue_for_response?) && ticket.overdue_for_response?

    case ticket.status.to_s
    when "submitted", "in_review"
      "helpdesk-badge--info"
    when "reopened"
      "helpdesk-badge--warning"
    when "resolved"
      "helpdesk-badge--danger"
    when "closed"
      "helpdesk-badge--success"
    else
      "helpdesk-badge--neutral"
    end
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
