class LimitHelpdeskEscalationLevelsToL2 < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:helpdesk_escalation_levels)

    execute "DELETE FROM helpdesk_escalation_levels WHERE position > 2"

    return unless table_exists?(:help_desk_tickets)
    return unless column_exists?(:help_desk_tickets, :current_escalation_position)

    execute "UPDATE help_desk_tickets SET current_escalation_position = 2 WHERE current_escalation_position > 2"

    return unless column_exists?(:help_desk_tickets, :escalation_due_at)

    execute "UPDATE help_desk_tickets SET escalation_due_at = NULL WHERE current_escalation_position >= 2"
  end

  def down
    # Removed escalation levels are not restored.
  end
end
