class EmployeeDetail < ApplicationRecord
  has_many :user_details, dependent: :destroy
  has_many :target_submissions, dependent: :destroy
  has_many :sms_logs, dependent: :destroy
  belongs_to :user, optional: true
  has_many :l1_pulse_assessments, dependent: :destroy
  has_many :user_training_assignments, dependent: :destroy
  has_many :assigned_trainings, through: :user_training_assignments, source: :training
  after_initialize :set_default_status, if: :new_record?
  # belongs_to :department  # only if you have a departments table and department_id column

  # Mobile number validation removed as requested

  def name
    employee_name
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      employee_id
      employee_name
      employee_email
      employee_code
      mobile_number
      l1_code
      l1_employer_name
      l2_code
      l2_employer_name
      post
      department
      created_at
      updated_at
    ]
  end


  enum :status, {
  pending: "pending",
  l1_approved: "l1_approved",
  l1_rejected: "l1_returned",
  l2_approved: "l2_approved",
  l2_returned: "l2_returned"
}

# app/models/employee_detail.rb
scope :l1_pending_records, -> { where(status: [ "pending", "returned" ]) }



  # ✅ Allow only safe associations (empty if none)
  def self.ransackable_associations(auth_object = nil)
    []
  end

  def set_default_status
   self.status ||= "pending"
  end
end
