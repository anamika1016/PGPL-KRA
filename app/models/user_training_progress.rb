class UserTrainingProgress < ApplicationRecord
  belongs_to :training
  belongs_to :user

  validates :status, inclusion: { in: %w[started completed] }, allow_nil: true

  scope :completed, -> { where(status: "completed") }
  scope :started,   -> { where(status: "started") }
end
