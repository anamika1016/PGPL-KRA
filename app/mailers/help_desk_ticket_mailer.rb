class HelpDeskTicketMailer < ApplicationMailer
  def ticket_assigned(ticket_id)
    @ticket = HelpDeskTicket.includes(:department, :submitted_by_user, :assigned_to_user).find(ticket_id)
    @assignee = @ticket.assigned_to_user

    mail(to: @assignee.email, subject: "#{@ticket.ticket_reference} assigned to you")
  end

  def ticket_resolved(ticket_id, recipients)
    @ticket = HelpDeskTicket.includes(:department, :submitted_by_user, :responded_by_user, :approval_user).find(ticket_id)

    mail(to: recipients, subject: "#{@ticket.ticket_reference} needs your action")
  end

  def ticket_updated(ticket_id)
    @ticket = HelpDeskTicket.includes(:department, :assigned_to_user).find(ticket_id)

    mail(to: @ticket.requester_email, subject: "#{@ticket.ticket_reference} updated")
  end

  def ticket_action(ticket_id, recipients)
    @ticket = HelpDeskTicket.includes(:department, :submitted_by_user, :assigned_to_user, :responded_by_user, :closed_by_user).find(ticket_id)
    @action_label = @ticket.status.to_s.humanize

    mail(to: recipients, subject: "#{@ticket.ticket_reference} action update")
  end
end
