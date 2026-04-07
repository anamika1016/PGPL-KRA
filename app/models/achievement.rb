class Achievement < ApplicationRecord
  belongs_to :user_detail
  has_one :achievement_remark, dependent: :destroy

  # validates :month, uniqueness: { scope: :user_detail_id }
  enum :status, {
      pending: "pending",
      l1_approved: "l1_approved",
      l1_returned: "l1_returned",
      l2_approved: "l2_approved",
      l2_returned: "l2_returned"
    }

  # FIXED: Ensure status is always set to pending by default
  before_validation :set_default_status, on: :create

  # FIXED: Validate that status is always present and valid
  validates :status, presence: true, inclusion: { in: statuses.keys }

  # FIXED: Ensure status can be updated to pending
  def reset_to_pending!
    update!(status: "pending")
  end

  # FIXED: Class method to reset all achievements in a quarter to pending
  def self.reset_quarter_to_pending!(quarter_months)
    where(month: quarter_months).update_all(
      status: "pending",
      l1_remarks: nil,
      l1_percentage: nil,
      l2_remarks: nil,
      l2_percentage: nil
    )
  end

  # Remove the presence validation since we're creating achievements without achievement values during approval
  # validates :achievement, presence: true

  private

  def set_default_status
    self.status ||= "pending"
  end
end
