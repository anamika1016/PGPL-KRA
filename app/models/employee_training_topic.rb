class EmployeeTrainingTopic < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_values

  validates :thematic_department_name, :name, presence: true
  validates :name, uniqueness: { scope: :thematic_department_name, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:thematic_department_name, :name) }

  private

  def normalize_values
    self.thematic_department_name = thematic_department_name.to_s.strip.presence
    self.name = name.to_s.strip.presence
  end
end
