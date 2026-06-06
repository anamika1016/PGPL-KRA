class HelpDeskRequesterRemark < ApplicationRecord
  belongs_to :help_desk_ticket
  belongs_to :user, optional: true

  validates :message, presence: true

  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }
  scope :latest_first, -> { order(created_at: :desc, id: :desc) }
end
