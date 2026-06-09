class EmployeeTraining < ApplicationRecord
  belongs_to :user

  has_one_attached :training_register
  has_one_attached :photo_upload

  before_validation :normalize_arrays
  before_validation :normalize_text_values

  validates :office_types, :office_names, presence: true
  validates :thematic_department_name, :training_date, :topic, :details, :training_location, :qr_id, presence: true
  validates :asa_participants, :other_participants, numericality: { greater_than_or_equal_to: 0 }

  validate :other_topic_presence
  validate :attachments_presence
  validate :attachments_are_allowed

  scope :recent_first, -> { order(training_date: :desc, created_at: :desc) }

  def display_topic
    topic == "__other__" ? other_topic.to_s : topic.to_s
  end

  def selected_employees
    EmployeeDetail.where(id: employee_detail_ids).order(:employee_code)
  end

  private

  def normalize_arrays
    self.office_types = Array(office_types).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    self.office_names = Array(office_names).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    self.employee_detail_ids = Array(employee_detail_ids).map(&:to_i).reject(&:zero?).uniq
  end

  def normalize_text_values
    self.thematic_department_name = thematic_department_name.to_s.strip.presence
    self.topic = topic.to_s.strip.presence
    self.other_topic = other_topic.to_s.strip.presence
    self.details = details.to_s.strip.presence
    self.training_location = training_location.to_s.strip.presence
    self.qr_id = qr_id.to_s.strip.presence
  end

  def attachments_are_allowed
    validate_attachment(training_register, "Training Register", %w[application/pdf image/jpeg image/jpg image/png], "PDF, JPG, or PNG")
    validate_attachment(photo_upload, "Photo Upload", %w[image/jpeg image/jpg image/png], "JPG or PNG")
  end

  def attachments_presence
    errors.add(:training_register, "is required") unless training_register.attached?
    errors.add(:photo_upload, "is required") unless photo_upload.attached?
  end

  def other_topic_presence
    errors.add(:other_topic, "is required") if topic == "__other__" && other_topic.blank?
  end

  def validate_attachment(attachment, label, allowed_content_types, allowed_label)
    return unless attachment.attached?

    unless allowed_content_types.include?(attachment.blob.content_type)
      errors.add(attachment.name, "#{label} must be #{allowed_label}")
    end

    if attachment.blob.byte_size > 10.megabytes
      errors.add(attachment.name, "#{label} must be less than 10MB")
    end
  end
end
