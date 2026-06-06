class HelpDeskQuestionMaster < ApplicationRecord
  REQUEST_TYPES = %w[ticket complaint suggestion].freeze

  belongs_to :department

  has_many :help_desk_tickets, dependent: :nullify

  enum :request_type, {
    ticket: "ticket",
    complaint: "complaint",
    suggestion: "suggestion"
  }

  scope :active, -> { where(active: true) }
  scope :ordered_for_display, -> {
    joins(:department).order("departments.department_type ASC, help_desk_question_masters.request_type ASC, help_desk_question_masters.position ASC, help_desk_question_masters.created_at ASC")
  }
  scope :for_request_context, ->(department_id, request_type) {
    where(department_id: department_id, request_type: request_type)
  }

  before_validation :normalize_question_text
  before_validation :assign_default_position, on: :create

  validates :department_id, presence: true
  validates :request_type, presence: true, inclusion: { in: REQUEST_TYPES }
  validates :question_text, presence: true, uniqueness: { scope: [ :department_id, :request_type ], case_sensitive: false }
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def request_label
    request_type.to_s.humanize
  end

  private

  def normalize_question_text
    self.question_text = question_text.to_s.strip.presence
  end

  def assign_default_position
    return if position.present?
    return if department_id.blank? || request_type.blank?

    self.position = self.class.for_request_context(department_id, request_type).maximum(:position).to_i + 1
  end
end
