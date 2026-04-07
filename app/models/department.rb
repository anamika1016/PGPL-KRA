  # class Department < ApplicationRecord
  #   has_many :activities, dependent: :destroy
  #   has_many :user_details

  #   accepts_nested_attributes_for :activities, allow_destroy: true, reject_if: :all_blank
  # end



  class Department < ApplicationRecord
  has_many :activities
  has_many :user_details

  accepts_nested_attributes_for :activities, allow_destroy: true, reject_if: :all_blank

  validates :department_type, presence: true
  # validates :employee_reference, presence: true

  # Callback to create UserDetail records when activities are created
  after_save :create_user_details_for_activities

  # Callback to handle activity updates and deletions
  after_update :sync_user_details_with_activities

  private

  def create_user_details_for_activities
    return unless employee_reference.present?

    # Find the employee
    employee = EmployeeDetail.find_by(employee_id: employee_reference)
    return unless employee

    # Create UserDetail records for each activity
    activities.each do |activity|
      # Check if UserDetail already exists to avoid duplicates
      existing_user_detail = UserDetail.find_by(
        department_id: id,
        activity_id: activity.id,
        employee_detail_id: employee.id
      )

      unless existing_user_detail
        UserDetail.create!(
          department_id: id,
          activity_id: activity.id,
          employee_detail_id: employee.id
        )
      end
    end
  end

  def sync_user_details_with_activities
    return unless employee_reference.present?

    # Find the employee
    employee = EmployeeDetail.find_by(employee_id: employee_reference)
    return unless employee

    # Get current activity IDs
    current_activity_ids = activities.pluck(:id)

    # Remove UserDetail records for activities that no longer exist
    UserDetail.where(
      department_id: id,
      employee_detail_id: employee.id
    ).where.not(activity_id: current_activity_ids).destroy_all

    # Create UserDetail records for new activities
    current_activity_ids.each do |activity_id|
      existing_user_detail = UserDetail.find_by(
        department_id: id,
        activity_id: activity_id,
        employee_detail_id: employee.id
      )

      unless existing_user_detail
        UserDetail.create!(
          department_id: id,
          activity_id: activity_id,
          employee_detail_id: employee.id
        )
      end
    end
  end

  # Get employee name from employee_reference (which stores employee_id)
  def employee_name
    employee = EmployeeDetail.find_by(employee_id: self.employee_reference)
    employee&.employee_name || "N/A"
  end

  # Get employee details
  def employee_detail
    EmployeeDetail.find_by(employee_id: self.employee_reference)
  end

  # Get employee code
  def employee_code
    employee = EmployeeDetail.find_by(employee_id: self.employee_reference)
    employee&.employee_code || "N/A"
  end

  # Get full employee display name with code
  def employee_display_name
    employee = EmployeeDetail.find_by(employee_id: self.employee_reference)
    if employee
      "#{employee.employee_name} (#{employee.employee_code})"
    else
      "N/A"
    end
  end
  end
