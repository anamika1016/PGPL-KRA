class HelpDeskEscalationJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = HelpDeskTicket.find_by(id: ticket_id)
    return if ticket.blank? || ticket.closed?

    if ticket.resolved?
      auto_closed = ticket.auto_close_if_requester_inactive!
      ticket.schedule_requester_response_check! if !auto_closed && ticket.requester_response_due_at.present? && ticket.requester_response_due_at > Time.current && ticket.resolved?
      return
    end

    escalated = ticket.auto_escalate_if_due!
    ticket.schedule_next_escalation_check! if !escalated && ticket.escalation_due_at.present? && ticket.escalation_due_at > Time.current && ticket.open_for_review_status?
  end
end
