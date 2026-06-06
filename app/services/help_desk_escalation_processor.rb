class HelpDeskEscalationProcessor
  CACHE_KEY = "help_desk/escalation_processor_last_run".freeze
  RUN_INTERVAL = 1.minute

  def self.process_if_due(reference_time: Time.current)
    return unless can_process?

    last_run_at = Rails.cache.read(CACHE_KEY)
    return if last_run_at.present? && last_run_at > reference_time - RUN_INTERVAL

    Rails.cache.write(CACHE_KEY, reference_time, expires_in: RUN_INTERVAL)
    process_overdue_tickets(reference_time: reference_time)
    process_requester_auto_closures(reference_time: reference_time)
  end

  def self.process_overdue_tickets(reference_time: Time.current)
    HelpDeskTicket.due_for_escalation(reference_time).find_each do |ticket|
      ticket.auto_escalate_if_due!(reference_time: reference_time)
    end
  end

  def self.process_requester_auto_closures(reference_time: Time.current)
    HelpDeskTicket.due_for_auto_close(reference_time).find_each do |ticket|
      ticket.auto_close_if_requester_inactive!(reference_time: reference_time)
    end
  end

  def self.can_process?
    HelpDeskTicket.table_exists?
  rescue ActiveRecord::ActiveRecordError
    false
  end
end
