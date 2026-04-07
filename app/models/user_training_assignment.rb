class UserTrainingAssignment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :training
  belongs_to :employee_detail, optional: true

  validates :training_id, uniqueness: {
    scope: :employee_detail_id,
    message: "already assigned for this employee"
  }
end
