class HelpdeskEscalationLevel < ApplicationRecord
  belongs_to :helpdesk_escalation_matrix, inverse_of: :escalation_levels
  belongs_to :user

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :user_id, presence: true
end
