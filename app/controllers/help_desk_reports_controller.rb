class HelpDeskReportsController < ApplicationController
  before_action :load_report_context

  def index
    respond_to do |format|
      format.html
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=\"help_desk_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.xlsx\""
      }
    end
  end

  private

  def load_report_context
    @departments = Department.selectable_verticals
    @report_tickets = filtered_report_tickets
    @report_generated_at = Time.current
    @active_filter_labels = build_active_filter_labels
    @report_scope_copy =
      if current_user.hod?
        "All help desk tickets across every department are saved here with their latest status and ownership trail."
      else
        "Tickets raised by you, submitted on your behalf, assigned to you, or resolved by you stay saved here as your help desk report."
      end
  end

  def filtered_report_tickets
    scope = HelpDeskTicket.visible_to_actor(current_user)
                          .includes(
                            :department,
                            :submitted_by_user,
                            { approval_user: :employee_detail },
                            { assigned_to_user: :employee_detail },
                            { responded_by_user: :employee_detail },
                            { closed_by_user: :employee_detail },
                            { user: :employee_detail },
                            { support_updates: { user: :employee_detail } },
                            { requester_remarks: { user: :employee_detail } },
                            documents_attachments: :blob,
                            support_documents_attachments: :blob,
                            requester_followup_documents_attachments: :blob
                          )

    filters = report_filter_params

    if HelpDeskTicket::STATUSES.include?(filters[:status].to_s)
      scope = scope.where(status: filters[:status])
    end

    if HelpDeskTicket::REQUEST_TYPES.include?(filters[:request_type].to_s)
      scope = scope.where(request_type: filters[:request_type])
    end

    if filters[:department_id].present?
      scope = scope.where(department_id: filters[:department_id])
    end

    if filters[:query].present?
      scope = apply_query_filter(scope, filters[:query])
    end

    scope.recent_first.to_a
  end

  def apply_query_filter(scope, raw_query)
    query = raw_query.to_s.strip
    return scope if query.blank?

    search_term = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    ticket_id = extract_ticket_id(query)
    searchable_columns = [
      "LOWER(requester_name) LIKE :term",
      "LOWER(requester_email) LIKE :term",
      "LOWER(COALESCE(requester_employee_code, '')) LIKE :term",
      "LOWER(COALESCE(question_subject, '')) LIKE :term",
      "LOWER(message) LIKE :term",
      "LOWER(COALESCE(response_message, '')) LIKE :term",
      "LOWER(COALESCE(requester_remark, '')) LIKE :term"
    ]

    if ticket_id.present?
      scope.where("(#{searchable_columns.join(' OR ')} OR id = :ticket_id)", term: search_term, ticket_id: ticket_id)
    else
      scope.where(searchable_columns.join(" OR "), term: search_term)
    end
  end

  def extract_ticket_id(query)
    normalized = query.to_s.strip.sub(/\Ahd-/i, "")
    return if normalized.blank? || normalized.match?(/\D/)

    normalized.to_i
  end

  def report_filter_params
    params.permit(:query, :status, :request_type, :department_id)
  end

  def build_active_filter_labels
    filters = report_filter_params
    labels = []

    if filters[:query].present?
      labels << "Search: #{filters[:query].to_s.strip}"
    end

    if filters[:department_id].present?
      department_name = @departments.find { |department| department.id == filters[:department_id].to_i }&.department_type
      labels << "Department: #{department_name}" if department_name.present?
    end

    if HelpDeskTicket::REQUEST_TYPES.include?(filters[:request_type].to_s)
      labels << "Request Type: #{filters[:request_type].to_s.humanize}"
    end

    if HelpDeskTicket::STATUSES.include?(filters[:status].to_s)
      labels << "Status: #{filters[:status].to_s.humanize}"
    end

    labels
  end
end
