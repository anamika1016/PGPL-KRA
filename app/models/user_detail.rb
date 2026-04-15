class UserDetail < ApplicationRecord
  MONTHS = %w[
    april may june july august september
    october november december january february march
  ].freeze
  DEFAULT_PREVIOUS_FINANCIAL_YEARS = 5
  DEFAULT_FUTURE_FINANCIAL_YEARS = 1

  belongs_to :department
  belongs_to :activity
  belongs_to :employee_detail, optional: true  # optional if it can be nil
  has_many :target_submissions, dependent: :destroy
  has_many :achievements, dependent: :destroy

  before_validation :assign_default_financial_year

  validates :financial_year, presence: true
  validate :activity_matches_department
  validate :employee_matches_department_reference
  validate :financial_year_matches_associations

  scope :for_financial_year, ->(financial_year) {
    normalized_year = normalize_financial_year(financial_year).presence || current_financial_year
    where(financial_year: normalized_year)
  }

  scope :assignment_consistent, -> {
    joins(:department, :activity)
      .left_joins(:employee_detail)
      .where("activities.department_id = user_details.department_id")
      .where(
        "departments.employee_reference IS NULL OR BTRIM(departments.employee_reference) = '' OR employee_details.id IS NULL OR departments.employee_reference = employee_details.employee_id OR departments.employee_reference = employee_details.employee_code"
      )
  }

  def self.current_financial_year(date = Time.zone.today)
    date = date.to_date
    start_year = date.month >= 4 ? date.year : date.year - 1
    "#{start_year}-#{(start_year + 1).to_s.last(2)}"
  end

  def self.available_financial_years(reference_date = Time.zone.today)
    years = where.not(financial_year: [ nil, "" ]).distinct.pluck(:financial_year)
    (default_financial_years(reference_date) + years)
      .map { |year| normalize_financial_year(year) }
      .reject(&:blank?)
      .uniq
      .sort_by { |year| financial_year_start(year) }
      .reverse
  end

  def self.default_financial_years(reference_date = Time.zone.today)
    current_start_year = financial_year_start(current_financial_year(reference_date))

    ((current_start_year - DEFAULT_PREVIOUS_FINANCIAL_YEARS)..(current_start_year + DEFAULT_FUTURE_FINANCIAL_YEARS)).map do |start_year|
      build_financial_year(start_year)
    end
  end

  def self.normalize_financial_year(value)
    return if value.blank?

    cleaned_value = value.to_s.strip

    case cleaned_value
    when /\A\d{4}-\d{2}\z/
      cleaned_value
    when /\A\d{4}[-\/]\d{4}\z/
      "#{cleaned_value[0, 4]}-#{cleaned_value[-2, 2]}"
    when /\A\d{4}\/\d{2}\z/
      cleaned_value.tr("/", "-")
    else
      cleaned_value
    end
  end

  def self.financial_year_start(value)
    normalize_financial_year(value).to_s.split("-").first.to_i
  end

  def self.build_financial_year(start_year)
    "#{start_year}-#{(start_year + 1).to_s.last(2)}"
  end

  def display_theme_name
    self[:theme_name].presence || activity&.theme_name
  end

  def display_unit
    self[:unit].presence || activity&.unit
  end

  private

  def assign_default_financial_year
    self.financial_year = self.class.normalize_financial_year(financial_year).presence || self.class.current_financial_year
  end

  def activity_matches_department
    return unless activity && department
    return if activity.department_id == department_id

    errors.add(:activity_id, "must belong to the selected department")
  end

  def employee_matches_department_reference
    return unless employee_detail && department&.employee_reference.present?
    return if employee_references.include?(department.employee_reference)

    errors.add(:employee_detail_id, "does not belong to the selected department")
  end

  def financial_year_matches_associations
    return if financial_year.blank?

    if department&.financial_year.present? && department.financial_year != financial_year
      errors.add(:financial_year, "must match the department financial year")
    end

    if activity&.financial_year.present? && activity.financial_year != financial_year
      errors.add(:financial_year, "must match the activity financial year")
    end
  end

  def employee_references
    [ employee_detail&.employee_id, employee_detail&.employee_code ].compact_blank
  end
end
