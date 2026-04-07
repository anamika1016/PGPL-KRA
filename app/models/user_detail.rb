class UserDetail < ApplicationRecord
  belongs_to :department
  belongs_to :activity
  belongs_to :employee_detail, optional: true  # optional if it can be nil
  has_many :target_submissions, dependent: :destroy
  has_many :achievements, dependent: :destroy
end
