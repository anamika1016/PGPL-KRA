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

  scope :for_financial_year, ->(financial_year) {
    normalized_year = normalize_financial_year(financial_year).presence || current_financial_year
    where(financial_year: normalized_year)
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
end
