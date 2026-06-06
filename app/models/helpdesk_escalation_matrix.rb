class HelpdeskEscalationMatrix < ApplicationRecord
  belongs_to :department

  has_many :escalation_levels,
           -> { order(:position) },
           class_name: "HelpdeskEscalationLevel",
           dependent: :destroy,
           inverse_of: :helpdesk_escalation_matrix

  accepts_nested_attributes_for :escalation_levels, allow_destroy: true

  validates :department_id, presence: true, uniqueness: true
  validate :must_have_at_least_one_escalation_level
  validate :escalation_levels_must_have_users

  before_validation :normalize_escalation_levels
  before_save :sync_legacy_level_columns

  scope :ordered_by_department, -> { joins(:department).order("departments.department_type ASC") }

  def build_default_escalations(minimum_levels = 3)
    return if escalation_levels.any?

    minimum_levels.times do |index|
      escalation_levels.build(position: index + 1)
    end
  end

  def ordered_levels
    escalation_levels.reject(&:marked_for_destruction?).sort_by { |level| level.position.to_i }
  end

  private

  def normalize_escalation_levels
    active_levels = escalation_levels.reject(&:marked_for_destruction?)

    active_levels.each_with_index do |level, index|
      level.position = index + 1
    end
  end

  def must_have_at_least_one_escalation_level
    return if escalation_levels.any? { |level| !level.marked_for_destruction? }

    errors.add(:base, "At least one escalation level is required")
  end

  def escalation_levels_must_have_users
    escalation_levels.each do |level|
      next if level.marked_for_destruction?
      next if level.user_id.present?

      errors.add(:base, "Each escalation level must have a selected user")
    end
  end

  def sync_legacy_level_columns
    return unless has_attribute?(:l1_user_id)

    levels = ordered_levels

    self.l1_user_id = levels[0]&.user_id
    self.l2_user_id = levels[1]&.user_id if has_attribute?(:l2_user_id)
    self.l3_user_id = levels[2]&.user_id if has_attribute?(:l3_user_id)
  end
end
