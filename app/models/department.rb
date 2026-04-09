class Department < ApplicationRecord
  has_many :activities
  has_many :user_details

  accepts_nested_attributes_for :activities, allow_destroy: true, reject_if: :all_blank

  validates :department_type, presence: true
  validates :financial_year, presence: true

  before_validation :assign_default_financial_year
  before_validation :assign_financial_year_to_activities

  after_save :create_user_details_for_activities
  after_update :sync_user_details_with_activities

  scope :for_financial_year, ->(financial_year) {
    normalized_year = UserDetail.normalize_financial_year(financial_year).presence || UserDetail.current_financial_year
    where(financial_year: normalized_year)
  }

  def employee_name
    employee_detail&.employee_name || "N/A"
  end

  def employee_detail
    EmployeeDetail.find_by(employee_id: employee_reference) ||
      EmployeeDetail.find_by(employee_code: employee_reference)
  end

  def employee_code
    employee_detail&.employee_code || "N/A"
  end

  def employee_display_name
    employee = employee_detail
    return "N/A" unless employee

    "#{employee.employee_name} (#{employee.employee_code.presence || employee.employee_id})"
  end

  private

  def assign_default_financial_year
    self.financial_year = UserDetail.normalize_financial_year(financial_year).presence || UserDetail.current_financial_year
  end

  def assign_financial_year_to_activities
    activities.each do |activity|
      activity.financial_year = financial_year
    end
  end

  def create_user_details_for_activities
    employee = employee_detail
    return unless employee

    activities.each do |activity|
      upsert_user_detail_for(activity, employee)
    end
  end

  def sync_user_details_with_activities
    employee = employee_detail
    return unless employee

    current_activity_ids = activities.pluck(:id)

    UserDetail.where(
      department_id: id,
      employee_detail_id: employee.id,
      financial_year: financial_year
    ).where.not(activity_id: current_activity_ids).destroy_all

    activities.each do |activity|
      upsert_user_detail_for(activity, employee)
    end
  end

  def upsert_user_detail_for(activity, employee)
    user_detail = UserDetail.find_or_initialize_by(
      department_id: id,
      activity_id: activity.id,
      employee_detail_id: employee.id,
      financial_year: financial_year
    )

    user_detail.theme_name = activity.theme_name
    user_detail.unit = activity.unit
    user_detail.save! if user_detail.new_record? || user_detail.changed?
  end
end
