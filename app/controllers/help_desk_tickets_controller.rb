class HelpDeskTicketsController < ApplicationController
  before_action :load_help_desk_context
  before_action :set_assigned_ticket, only: :respond
  before_action :authorize_help_desk_response!, only: :respond
  before_action :set_requester_action_ticket, only: :finalize_resolution
  before_action :authorize_help_desk_finalization!, only: :finalize_resolution

  def index
    @help_desk_ticket = current_user.help_desk_tickets.new
  end

  def assigned_queue
    unless @can_review_help_desk_tickets
      redirect_to help_desk_tickets_path, alert: "You are not authorized to access assigned help desk tickets."
      return
    end
  end

  def create
    @help_desk_ticket = build_help_desk_ticket

    if @help_desk_ticket.errors.any?
      render :index, status: :unprocessable_entity
    elsif @help_desk_ticket.save
      notice =
        if @help_desk_ticket.assisted_request?
          "Oral help desk request has been submitted on behalf of #{@help_desk_ticket.requester_name}."
        else
          "Your help desk request has been submitted successfully."
        end

      redirect_to help_desk_tickets_path, notice: notice
    else
      render :index, status: :unprocessable_entity
    end
  end

  def respond
    decision = review_decision_param
    selected_approval_user = approval_user_param if %w[send_for_approval close close_ticket].include?(decision)

    success =
      if %w[send_for_approval close close_ticket].include?(decision) && params[:approval_user_id].present? && selected_approval_user.blank?
        @assigned_ticket.errors.add(:approval_user, "must be requester or original submitter")
        false
      else
        case decision
        when "keep_open"
          @assigned_ticket.keep_open_by(
            reviewer: current_user,
            response_message: response_message_param,
            support_documents: support_documents_param
          )
        when "forward"
          @assigned_ticket.forward_to_department_by(
            reviewer: current_user,
            department: forward_department_param,
            response_message: response_message_param,
            support_documents: support_documents_param
          )
        when "send_for_approval", "close", "close_ticket"
          @assigned_ticket.mark_resolved_by(
            reviewer: current_user,
            response_message: response_message_param,
            approval_user: selected_approval_user,
            final_action_mode: @assigned_ticket.assisted_request? ? "approve_reject" : "reopen_close",
            support_documents: support_documents_param
          )
        else
          @assigned_ticket.errors.add(:base, "Choose whether you want to keep this ticket open or close it.")
          false
        end
      end

    if success
      notice =
        if decision == "forward"
          "Ticket forwarded to #{@assigned_ticket.department.department_type}. The new department has been notified."
        elsif decision == "keep_open"
          "Update shared successfully. The ticket is still open with support and can continue without any user action yet."
        else
          approval_name = @assigned_ticket.approval_pending_user&.display_name.presence || "the selected user"
          action_label = @assigned_ticket.final_action_mode_approve_reject? ? "approve or reject" : "reopen it or close it"
          "Ticket marked as completed and shared with #{approval_name}. They can #{action_label} within 2 days."
        end

      redirect_to response_redirect_path, notice: notice
    else
      @help_desk_ticket = current_user.help_desk_tickets.new
      @assigned_tickets = @assigned_tickets.map { |ticket| ticket.id == @assigned_ticket.id ? @assigned_ticket : ticket }
      if return_to_assigned_queue?
        render :assigned_queue, status: :unprocessable_entity
      else
        render :index, status: :unprocessable_entity
      end
    end
  end

  def finalize_resolution
    decision = requester_decision_param

    success =
      case decision
      when "reject", "reopen", "reverse"
        @requester_action_ticket.reject_by!(
          actor: current_user,
          remark: requester_remark_param,
          requester_followup_documents: requester_followup_documents_param
        )
      when "approve", "close"
        @requester_action_ticket.approve_by!(actor: current_user)
      else
        action_text = @requester_action_ticket.final_action_mode_approve_reject? ? "approve or reject" : "reopen or close"
        @requester_action_ticket.errors.add(:base, "Choose whether you want to #{action_text} this ticket.")
        false
      end

    if success
      notice =
        if %w[reject reopen reverse].include?(decision)
          @requester_action_ticket.final_action_mode_approve_reject? ? "Response ticket rejected and sent back with your remark." : "Ticket reopened successfully and sent back to support with your remark."
        else
          @requester_action_ticket.final_action_mode_approve_reject? ? "Response ticket approved successfully." : "Ticket closed successfully."
        end
      redirect_to help_desk_tickets_path, notice: notice
    else
      @help_desk_ticket = current_user.help_desk_tickets.new
      @recent_tickets = @recent_tickets.map { |ticket| ticket.id == @requester_action_ticket.id ? @requester_action_ticket : ticket }
      render :index, status: :unprocessable_entity
    end
  end

  private

  def load_help_desk_context
    @requester_profile = current_user.mapped_employee_detail
    @departments = Department.selectable_verticals
    @can_review_help_desk_tickets = helpdesk_reviewer?
    @help_desk_requester_directory = build_help_desk_requester_directory
    @can_create_assisted_help_desk_tickets = @help_desk_requester_directory.any?
    @help_desk_requester_options = @help_desk_requester_directory.map { |requester| [ requester[:label], requester[:id] ] }
    @help_desk_question_catalog = build_help_desk_question_catalog
    @recent_tickets = load_recent_tickets
    @assigned_tickets = load_assigned_tickets
  end

  def help_desk_ticket_params
    params.require(:help_desk_ticket).permit(:department_id, :request_type, :initial_escalation_position, :question_subject, :help_desk_question_master_id, :message, :requester_user_id, :on_behalf_requested, :request_received_on, :request_received_time, documents: [])
  end

  def response_message_param
    params.require(:help_desk_ticket).fetch(:response_message, "")
  end

  def review_decision_param
    params[:review_decision].to_s.presence || "close"
  end

  def requester_decision_param
    params[:decision].to_s
  end

  def requester_remark_param
    params.fetch(:help_desk_ticket, {}).fetch(:requester_remark, "")
  end

  def support_documents_param
    params.fetch(:help_desk_ticket, {}).fetch(:support_documents, [])
  end

  def forward_department_param
    Department.find_by(id: params[:forward_department_id])
  end

  def requester_followup_documents_param
    params.fetch(:help_desk_ticket, {}).fetch(:requester_followup_documents, [])
  end

  def return_to_assigned_queue?
    ActiveModel::Type::Boolean.new.cast(params[:return_to_assigned_queue])
  end

  def response_redirect_path
    return assigned_queue_help_desk_tickets_path if return_to_assigned_queue?

    help_desk_tickets_path
  end

  def approval_user_param
    selected_id = params[:approval_user_id].to_s.presence
    return @assigned_ticket.approval_pending_user if selected_id.blank?

    @assigned_ticket.approval_candidate_users.find { |candidate| candidate.id == selected_id.to_i }
  end

  def load_assigned_tickets
    return HelpDeskTicket.none unless @can_review_help_desk_tickets

    scope = HelpDeskTicket.open_for_review
                          .includes(
                            :department,
                            :submitted_by_user,
                            { user: :employee_detail },
                            { assigned_to_user: :employee_detail },
                            { approval_user: :employee_detail },
                            { requester_remarks: { user: :employee_detail } },
                            documents_attachments: :blob,
                            support_documents_attachments: :blob,
                            requester_followup_documents_attachments: :blob
                          )
                          .recent_first

    scope.assigned_to(current_user).limit(12)
  end

  def load_recent_tickets
    includes_config = [
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
    ]

    current_statuses = HelpDeskTicket::REVIEW_OPEN_STATUSES + ["resolved"]

    HelpDeskTicket.user_side_visible_to_actor(current_user)
                  .where(status: current_statuses)
                  .includes(*includes_config)
                  .recent_first
                  .to_a
                  .select { |ticket| ticket.visible_in_user_current_list_for?(current_user) }
                  .first(10)
  end

  def set_assigned_ticket
    @assigned_ticket = HelpDeskTicket.includes(:department, :submitted_by_user, { user: :employee_detail }, { assigned_to_user: :employee_detail }, { responded_by_user: :employee_detail }, { approval_user: :employee_detail }, documents_attachments: :blob, support_documents_attachments: :blob, requester_followup_documents_attachments: :blob)
                                     .find(params[:id])
  end

  def set_requester_action_ticket
    @requester_action_ticket = HelpDeskTicket.includes(:department, :submitted_by_user, { user: :employee_detail }, { assigned_to_user: :employee_detail }, { responded_by_user: :employee_detail }, { closed_by_user: :employee_detail }, { approval_user: :employee_detail }, documents_attachments: :blob, support_documents_attachments: :blob, requester_followup_documents_attachments: :blob)
                                             .find(params[:id])
  end

  def authorize_help_desk_response!
    return if @assigned_ticket.can_be_responded_by?(current_user)

    redirect_to help_desk_tickets_path, alert: "You are not authorized to respond to this help desk request."
  end

  def authorize_help_desk_finalization!
    return if @requester_action_ticket.can_be_finalized_by?(current_user)

    redirect_to help_desk_tickets_path, alert: "You are not authorized to take action on this help desk ticket."
  end

  def build_help_desk_ticket
    ticket = current_user.help_desk_tickets.new(help_desk_ticket_params)
    ticket.submitted_by_user = current_user

    assisted_requested = ActiveModel::Type::Boolean.new.cast(ticket.on_behalf_requested)
    return ticket unless assisted_requested

    unless can_create_assisted_help_desk_tickets?
      ticket.errors.add(:base, "You are not allowed to raise an oral response ticket right now.")
      return ticket
    end

    requester_user = User.find_by(id: ticket.requester_user_id)
    if requester_user.blank?
      ticket.errors.add(:requester_user_id, "Please select the employee for whom you are raising this response ticket.")
      return ticket
    end

    if requester_user == current_user
      ticket.errors.add(:requester_user_id, "Choose another employee or turn off on behalf mode.")
      return ticket
    end

    unless allowed_assisted_requester_ids.include?(requester_user.id)
      ticket.errors.add(:requester_user_id, "You can raise an oral response ticket only for an available employee.")
      return ticket
    end

    ticket.user = requester_user
    ticket.raised_on_behalf = true if ticket.has_attribute?(:raised_on_behalf)
    ticket.prepare_assisted_resolution!(resolver: current_user)
    ticket
  end

  def build_help_desk_requester_directory
    users = User.includes(:employee_detail).where.not(id: current_user.id).to_a

    users.map do |user|
      employee_profile = user.mapped_employee_detail
      identifier = employee_profile&.employee_code.presence || user.employee_code.presence || user.email

      {
        id: user.id,
        label: "#{user.display_name} (#{identifier})",
        name: user.display_name,
        employee_code: identifier,
        email: user.email
      }
    end.sort_by { |requester| requester[:label].downcase }
  end

  def can_create_assisted_help_desk_tickets?
    @can_create_assisted_help_desk_tickets
  end

  def allowed_assisted_requester_ids
    @allowed_assisted_requester_ids ||= @help_desk_requester_directory.map { |requester| requester[:id] }
  end

  def direct_report_requester_users
    manager_code = current_user.employee_code.to_s.strip
    manager_email = current_user.email.to_s.strip.downcase
    conditions = []
    values = {}

    if manager_code.present?
      conditions << "TRIM(l1_code) = :manager_code"
      values[:manager_code] = manager_code
    end

    if manager_email.present?
      conditions << "LOWER(COALESCE(l1_employer_name, '')) = :manager_email"
      values[:manager_email] = manager_email
    end

    return [] if conditions.empty?

    employee_details = EmployeeDetail.includes(:user).where(conditions.join(" OR "), values)

    employee_details.filter_map do |employee_detail|
      user =
        employee_detail.user ||
        User.find_by(employee_code: employee_detail.employee_code.to_s.strip) ||
        User.find_by("LOWER(email) = ?", employee_detail.employee_email.to_s.strip.downcase)

      user if user.present? && user.id != current_user.id
    end.uniq { |user| user.id }
  end

  def build_help_desk_question_catalog
    HelpDeskQuestionMaster.active
                          .order(:department_id, :request_type, :position, :created_at)
                          .map do |question|
      {
        id: question.id,
        department_id: question.department_id,
        request_type: question.request_type,
        question_text: question.question_text
      }
    end
  end
end
