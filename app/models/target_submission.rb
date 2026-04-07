class TargetSubmission < ApplicationRecord
  belongs_to :user_detail
  belongs_to :user
  belongs_to :employee_detail
end
