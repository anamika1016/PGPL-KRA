class EmployeeTrainingThematic < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_values

  validates :thematic_type, :department_name, presence: true
  validates :department_name, uniqueness: { scope: :thematic_type, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:thematic_type, :department_name) }

  def display_name
    return thematic_type if thematic_type == department_name

    "#{thematic_type} - #{department_name}"
  end

  private

  def normalize_values
    self.thematic_type = thematic_type.to_s.strip.presence
    self.department_name = department_name.to_s.strip.presence
  end
end
