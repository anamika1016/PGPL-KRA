class HelpDeskTicket < ApplicationRecord
  DISPLAY_TIME_ZONE = "Asia/Kolkata".freeze
  REQUEST_TYPES = %w[ticket complaint suggestion].freeze
  STATUSES = %w[submitted in_review reopened resolved closed].freeze
  FINAL_ACTION_MODES = %w[reopen_close approve_reject].freeze
  ESCALATION_RESPONSE_WINDOW = 2.days
  REQUESTER_RESPONSE_WINDOW = 2.days
  REVIEW_OPEN_STATUSES = %w[submitted in_review reopened].freeze
  MAX_DOCUMENTS = 5
  MAX_DOCUMENT_SIZE = 10.megabytes

  belongs_to :user
  belongs_to :department
  belongs_to :assigned_to_user, class_name: "User", optional: true
  belongs_to :responded_by_user, class_name: "User", optional: true
  belongs_to :closed_by_user, class_name: "User", optional: true
  belongs_to :submitted_by_user, class_name: "User", optional: true
  belongs_to :approval_user, class_name: "User", optional: true
  belongs_to :help_desk_question_master, optional: true
  has_many :support_updates, class_name: "HelpDeskSupportUpdate", dependent: :destroy
  has_many :requester_remarks, class_name: "HelpDeskRequesterRemark", dependent: :destroy

  attr_accessor :requester_user_id, :on_behalf_requested, :request_received_on, :request_received_time, :initial_escalation_position

  has_many_attached :documents
  has_many_attached :support_documents
  has_many_attached :requester_followup_documents

  enum :request_type, {
    ticket: "ticket",
    complaint: "complaint",
    suggestion: "suggestion"
  }

  enum :status, {
    submitted: "submitted",
    in_review: "in_review",
    reopened: "reopened",
    resolved: "resolved",
    closed: "closed"
  }

  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }
  scope :open_for_review, -> { where(status: REVIEW_OPEN_STATUSES) }
  scope :pending_requester_confirmation, -> { where(status: "resolved") }
  scope :assigned_to, ->(reviewer) { where(assigned_to_user_id: reviewer.id) }
  scope :user_side_visible_to_actor, ->(actor) {
    next none if actor.blank?

    where(approval_user_id: actor.id)
      .or(matching_requester_identity(actor))
  }
  scope :visible_to_actor, ->(actor) {
    next none if actor.blank?
    next all if actor.hod?

    where(user_id: actor.id)
      .or(where(submitted_by_user_id: actor.id))
      .or(where(approval_user_id: actor.id))
      .or(where(assigned_to_user_id: actor.id))
      .or(where(responded_by_user_id: actor.id))
      .or(matching_requester_identity(actor))
  }
  scope :due_for_escalation, ->(reference_time = Time.current) {
    open_for_review.where.not(escalation_due_at: nil)
                   .where("escalation_due_at <= ?", reference_time)
  }
  scope :due_for_auto_close, ->(reference_time = Time.current) {
    pending_requester_confirmation.where.not(requester_response_due_at: nil)
                                  .where("requester_response_due_at <= ?", reference_time)
  }

  before_validation :populate_requester_details, on: :create
  before_validation :normalize_question_subject
  before_validation :populate_question_subject_from_master
  before_validation :normalize_message
  before_validation :normalize_response_message
  before_validation :populate_request_received_at_for_assisted_request, on: :create
  before_validation :set_default_status, on: :create
  before_validation :set_default_submitter, on: :create
  before_validation :assign_initial_escalation_details, on: :create
  after_commit :schedule_initial_escalation_check, on: :create
  after_commit :record_initial_support_update, on: :create
  after_commit :send_assignment_notifications, on: :create
  after_commit :send_assignment_notifications_for_reassignment, on: :update
  after_commit :send_resolution_notifications, on: :update

  validates :department_id, presence: true
  validates :request_type, presence: true, inclusion: { in: REQUEST_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :requester_name, :requester_email, presence: true

  validate :question_subject_presence_for_selected_type
  validate :question_master_matches_request_context
  validate :message_presence_for_selected_type
  validate :department_has_escalation_matrix, on: :create
  validate :request_received_on_required_for_assisted_request
  validate :request_received_time_required_for_assisted_request
  validate :request_received_on_cannot_be_in_future
  validate :response_message_required_for_resolution
  validate :approval_user_presence_for_confirmation
  validate :final_action_mode_presence_for_confirmation
  validate :documents_are_allowed

  def request_label
    request_type.to_s.humanize
  end

  def request_subject
    question_subject.presence || "No topic selected"
  end

  def ticket_reference
    return "Pending Ticket" if id.blank?

    "HD-#{id.to_s.rjust(5, '0')}"
  end

  def assisted_request?
    raised_on_behalf?
  end

  def submission_mode_label
    return "Self Submitted" unless assisted_request?
    return "Oral Response Ticket" if request_received_at.present?

    "Assisted Submission"
  end

  def open_for_review_status?
    REVIEW_OPEN_STATUSES.include?(status)
  end

  def current_escalation_label
    return "Response Ticket" if assisted_request?

    "L#{current_escalation_position.presence || 1} Escalation"
  end

  def approval_candidate_users
    [ user, submitted_by_user ].compact.uniq { |candidate| candidate.id }
  end

  def approval_pending_user
    approval_user.presence || approval_candidate_users.first
  end

  def final_action_mode_reopen_close?
    final_action_mode == "reopen_close"
  end

  def final_action_mode_approve_reject?
    final_action_mode == "approve_reject"
  end

  def final_action_mode_label
    case final_action_mode
    when "approve_reject"
      "Approve / Reject"
    when "reopen_close"
      "Reopen / Close"
    else
      "Pending User Action"
    end
  end

  def total_reopens
    reopen_count.to_i
  end

  def support_update_history
    updates = support_updates.oldest_first.to_a
    return updates if updates.any?
    return [] if response_message.blank?

    [
      SupportUpdateSnapshot.new(
        message: response_message,
        user: responded_by_user,
        created_at: responded_at.presence || updated_at.presence || created_at
      )
    ]
  end

  def support_update_history_latest_first
    support_update_history.reverse
  end

  def latest_support_update
    support_updates.latest_first.first || support_update_history.last
  end

  def requester_remark_history
    remarks = requester_remarks.oldest_first.to_a
    return remarks if remarks.any?
    return [] if requester_remark.blank?

    [
      RequesterRemarkSnapshot.new(
        message: requester_remark,
        user: approval_pending_user,
        created_at: updated_at.presence || created_at
      )
    ]
  end

  def requester_remark_history_latest_first
    requester_remark_history.reverse
  end

  def latest_requester_remark
    requester_remarks.latest_first.first || requester_remark_history.last
  end

  def overdue_for_response?(reference_time = Time.current)
    escalation_due_at.present? && escalation_due_at <= reference_time && open_for_review_status?
  end

  def can_be_responded_by?(reviewer)
    reviewer.present? && open_for_review_status? && (reviewer.hod? || assigned_to_user_id == reviewer.id)
  end

  def can_be_finalized_by?(actor)
    return false if actor.blank? || !resolved?
    return true if final_action_user_ids.include?(actor.id)
    return true if assisted_request? && requester_identity_matches?(actor)

    approval_identity_matches?(actor)
  end

  def visible_in_user_current_list_for?(actor)
    return false if actor.blank?
    return true if approval_user_id == actor.id

    requester_identity_matches?(actor)
  end

  def self.pending_user_action_for(actor)
    return none if actor.blank?

    pending_requester_confirmation.where(approval_user_id: actor.id)
                                  .or(pending_requester_confirmation.where(raised_on_behalf: true).matching_requester_identity(actor))
  end

  def self.matching_requester_identity(actor)
    return none if actor.blank?

    conditions = []
    values = {}

    email = actor.email.to_s.strip.downcase
    if email.present?
      conditions << "LOWER(COALESCE(requester_email, '')) = :email"
      values[:email] = email
    end

    employee_code = actor.employee_code.to_s.strip
    if employee_code.present?
      conditions << "TRIM(COALESCE(requester_employee_code, '')) = :employee_code"
      values[:employee_code] = employee_code
    end

    return none if conditions.blank?

    where(conditions.join(" OR "), values)
  end

  def prepare_assisted_resolution!(resolver:)
    resolved_at = Time.current

    self.raised_on_behalf = true if has_attribute?(:raised_on_behalf)
    self.submitted_by_user = resolver
    self.responded_by_user = resolver
    self.approval_user = user
    self.final_action_mode = "approve_reject"
    self.response_message = "Response ticket submitted by #{resolver.display_name} after completing the oral request."
    self.responded_at = resolved_at
    self.status = "resolved"
    self.requester_response_due_at = resolved_at + REQUESTER_RESPONSE_WINDOW
    self.assigned_to_user = nil
    self.assigned_at = nil
    self.escalation_due_at = nil
    self.closed_at = nil if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)
  end

  def auto_escalate_if_due!(reference_time: Time.current)
    return false if assisted_request?
    return false unless overdue_for_response?(reference_time)

    levels = configured_escalation_levels
    return false if levels.blank?

    changed = false

    while escalation_due_at.present? && escalation_due_at <= reference_time
      next_level = levels.find { |level| level.position.to_i > current_escalation_position.to_i }
      break if next_level.blank?

      next_assignment_time = escalation_due_at

      self.current_escalation_position = next_level.position
      self.assigned_to_user = next_level.user
      self.assigned_at = next_assignment_time
      self.escalation_due_at = next_assignment_time + ESCALATION_RESPONSE_WINDOW
      self.status = "in_review" if submitted?
      changed = true
    end

    return false unless changed

    save!
    schedule_next_escalation_check!
    true
  end

  def mark_resolved_by(reviewer:, response_message:, approval_user: nil, final_action_mode: "reopen_close", support_documents: [])
    new_response_message = response_message.to_s.strip.presence
    if response_message.blank? || new_response_message.blank?
      errors.add(:response_message, "can't be blank")
      return false
    end

    selected_final_action_mode = final_action_mode.to_s.presence || "reopen_close"
    unless FINAL_ACTION_MODES.include?(selected_final_action_mode)
      errors.add(:final_action_mode, "must be close ticket or send for approval")
      return false
    end

    selected_approval_user = approval_user.presence || approval_candidate_users.first
    if selected_approval_user.blank?
      errors.add(:approval_user, "must be selected before sending this ticket for user action")
      return false
    end

    unless approval_candidate_users.map(&:id).include?(selected_approval_user.id)
      errors.add(:approval_user, "must be requester or original submitter")
      return false
    end

    ensure_legacy_support_update!
    self.response_message = new_response_message

    update_time = Time.current

    self.responded_by_user = reviewer
    self.approval_user = selected_approval_user
    self.final_action_mode = selected_final_action_mode
    self.responded_at = update_time
    self.status = "resolved"
    self.escalation_due_at = nil
    self.requester_response_due_at = update_time + REQUESTER_RESPONSE_WINDOW
    self.closed_at = nil if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)
    attach_documents_to(:support_documents, support_documents)

    saved = save
    if saved
      record_support_update!(reviewer: reviewer, message: self.response_message, created_at: update_time)
      schedule_requester_response_check!
    end
    saved
  end

  def keep_open_by(reviewer:, response_message:, support_documents: [])
    new_response_message = response_message.to_s.strip.presence
    if response_message.blank? || new_response_message.blank?
      errors.add(:response_message, "can't be blank")
      return false
    end
    ensure_legacy_support_update!
    self.response_message = new_response_message

    update_time = Time.current

    self.responded_by_user = reviewer
    self.responded_at = update_time
    self.status = "in_review"
    self.assigned_to_user = reviewer
    self.assigned_at = update_time
    self.escalation_due_at = update_time + ESCALATION_RESPONSE_WINDOW
    self.approval_user = nil
    self.final_action_mode = nil
    self.requester_response_due_at = nil
    self.closed_at = nil if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)
    attach_documents_to(:support_documents, support_documents)

    saved = save
    if saved
      record_support_update!(reviewer: reviewer, message: self.response_message, created_at: update_time)
      schedule_next_escalation_check!
    end
    saved
  end

  def forward_to_department_by(reviewer:, department:, response_message:, support_documents: [])
    target_department = department
    new_response_message = response_message.to_s.strip.presence

    if target_department.blank?
      errors.add(:department, "must be selected before forwarding this ticket")
      return false
    end

    if target_department.id == department_id
      errors.add(:department, "must be different from the current department")
      return false
    end

    if new_response_message.blank?
      errors.add(:response_message, "can't be blank")
      return false
    end

    next_level = target_department.helpdesk_escalation_matrix&.ordered_levels&.first
    if next_level.blank?
      errors.add(:department, "does not have a configured helpdesk escalation matrix")
      return false
    end

    ensure_legacy_support_update!
    update_time = Time.current

    self.response_message = new_response_message
    self.responded_by_user = reviewer
    self.responded_at = update_time
    self.department = target_department
    self.status = "in_review"
    self.current_escalation_position = next_level.position
    self.assigned_to_user = next_level.user
    self.assigned_at = update_time
    self.escalation_due_at = update_time + ESCALATION_RESPONSE_WINDOW
    self.approval_user = nil
    self.final_action_mode = nil
    self.requester_response_due_at = nil
    self.closed_at = nil if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)
    attach_documents_to(:support_documents, support_documents)

    saved = save
    if saved
      record_support_update!(reviewer: reviewer, message: self.response_message, created_at: update_time)
      schedule_next_escalation_check!
    end
    saved
  end

  def reopen_by!(actor:, remark:, requester_followup_documents: [])
    unless can_be_finalized_by?(actor)
      errors.add(:base, "You are not authorized to reopen this ticket.")
      return false
    end

    new_requester_remark = remark.to_s.strip.presence
    if new_requester_remark.blank?
      errors.add(:requester_remark, "can't be blank")
      return false
    end
    ensure_legacy_requester_remark!
    self.requester_remark = new_requester_remark

    assignment_time = Time.current
    return_user = responded_by_user.presence || assigned_to_user
    return_position = current_escalation_position.presence

    if return_user.blank? || return_position.blank?
      first_level = configured_escalation_levels.first
      if first_level.blank?
        errors.add(:department_id, "does not have a configured helpdesk escalation matrix")
        return false
      end

      return_user = first_level.user
      return_position = first_level.position
    end

    self.status = "reopened"
    self.reopen_count = total_reopens + 1
    self.current_escalation_position = return_position
    self.assigned_to_user = return_user
    self.assigned_at = assignment_time
    self.escalation_due_at = assisted_request? ? nil : assignment_time + ESCALATION_RESPONSE_WINDOW
    self.approval_user = nil
    self.final_action_mode = nil
    self.requester_response_due_at = nil
    self.closed_at = nil if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)
    attach_documents_to(:requester_followup_documents, requester_followup_documents)

    saved = save
    if saved
      record_requester_remark!(actor: actor, message: requester_remark, created_at: assignment_time)
      schedule_next_escalation_check!
    end
    saved
  end

  def close_by!(actor:)
    unless can_be_finalized_by?(actor)
      errors.add(:base, "You are not authorized to close this ticket.")
      return false
    end

    self.status = "closed"
    self.requester_response_due_at = nil
    self.escalation_due_at = nil
    self.closed_at = Time.current if has_attribute?(:closed_at)
    self.closed_by_user = actor if has_attribute?(:closed_by_user_id)
    self.closed_automatically = false if has_attribute?(:closed_automatically)

    save
  end

  def approve_by!(actor:)
    close_by!(actor: actor)
  end

  def reject_by!(actor:, remark:, requester_followup_documents: [])
    reopen_by!(actor: actor, remark: remark, requester_followup_documents: requester_followup_documents)
  end

  def auto_close_if_requester_inactive!(reference_time: Time.current)
    return false unless resolved?
    return false if requester_response_due_at.blank? || requester_response_due_at > reference_time

    self.status = "closed"
    self.requester_response_due_at = nil
    self.escalation_due_at = nil
    self.closed_at = reference_time if has_attribute?(:closed_at)
    self.closed_by_user = nil if has_attribute?(:closed_by_user_id)
    self.closed_automatically = true if has_attribute?(:closed_automatically)

    save!
    true
  end

  def schedule_next_escalation_check!
    return if assisted_request?
    return unless open_for_review_status?
    return if escalation_due_at.blank?
    return if escalation_due_at <= Time.current

    HelpDeskEscalationJob.set(wait_until: escalation_due_at).perform_later(id)
  end

  def schedule_requester_response_check!
    return unless resolved?
    return if requester_response_due_at.blank?
    return if requester_response_due_at <= Time.current

    HelpDeskEscalationJob.set(wait_until: requester_response_due_at).perform_later(id)
  end

  private

  SupportUpdateSnapshot = Struct.new(:message, :user, :created_at, keyword_init: true)
  RequesterRemarkSnapshot = Struct.new(:message, :user, :created_at, keyword_init: true)

  def final_action_user_ids
    if approval_user_id.present?
      [ approval_user_id ]
    else
      approval_candidate_users.map(&:id)
    end
  end

  def requester_identity_matches?(actor)
    return false if actor.blank?

    actor_email = actor.email.to_s.strip.downcase
    actor_employee_code = actor.employee_code.to_s.strip
    requester_email_value = requester_email.to_s.strip.downcase
    requester_employee_code_value = requester_employee_code.to_s.strip

    (actor_email.present? && requester_email_value == actor_email) ||
      (actor_employee_code.present? && requester_employee_code_value == actor_employee_code)
  end

  def approval_identity_matches?(actor)
    return false if actor.blank? || approval_user.blank?

    actor_email = actor.email.to_s.strip.downcase
    actor_employee_code = actor.employee_code.to_s.strip
    approval_email = approval_user.email.to_s.strip.downcase
    approval_employee_code = approval_user.employee_code.to_s.strip

    (actor_email.present? && approval_email == actor_email) ||
      (actor_employee_code.present? && approval_employee_code == actor_employee_code)
  end

  def configured_escalation_levels
    department&.helpdesk_escalation_matrix&.ordered_levels.to_a
  end

  def populate_requester_details
    return unless user.present?

    employee_profile = user.mapped_employee_detail

    self.requester_name = user.display_name if requester_name.blank?
    self.requester_email = user.email if requester_email.blank?
    self.requester_employee_code = employee_profile&.employee_code.presence || user.employee_code if requester_employee_code.blank?
  end

  def normalize_question_subject
    self.question_subject = question_subject.to_s.strip.presence
  end

  def populate_request_received_at_for_assisted_request
    return unless assisted_request_requested?
    return if request_received_at.present?
    return if request_received_on.blank? || request_received_time.blank?

    parsed_date = Date.iso8601(request_received_on.to_s)
    parsed_time = display_time_zone.parse(request_received_time.to_s)
    raise ArgumentError if parsed_time.blank?

    self.request_received_at = display_time_zone.local(
      parsed_date.year,
      parsed_date.month,
      parsed_date.day,
      parsed_time.hour,
      parsed_time.min,
      0
    )
  rescue ArgumentError
    errors.add(:request_received_on, "must be a valid date")
  rescue TypeError
    errors.add(:request_received_time, "must be a valid time")
  end

  def populate_question_subject_from_master
    return if help_desk_question_master.blank?

    self.question_subject = help_desk_question_master.question_text
  end

  def normalize_message
    self.message = message.to_s.strip.presence
  end

  def normalize_response_message
    self.response_message = response_message.to_s.strip.presence
  end

  def set_default_status
    self.status ||= "submitted"
  end

  def set_default_submitter
    self.submitted_by_user ||= user
    if has_attribute?(:raised_on_behalf)
      self.raised_on_behalf = submitted_by_user.present? && user.present? && submitted_by_user_id != user_id
    end
  end

  def assign_initial_escalation_details
    return unless department.present?
    return if assisted_request?
    return if assigned_to_user_id.present?

    selected_level = initial_escalation_level
    return if selected_level.blank?

    assignment_time = Time.current

    self.current_escalation_position ||= selected_level.position
    self.assigned_to_user = selected_level.user
    self.assigned_at ||= assignment_time
    self.escalation_due_at ||= assignment_time + ESCALATION_RESPONSE_WINDOW
  end

  def initial_escalation_level
    levels = configured_escalation_levels
    requested_position = initial_escalation_position.to_i

    levels.find { |level| level.position.to_i == requested_position } || levels.first
  end

  def message_presence_for_selected_type
    return if request_type.blank?
    return if message.present?

    label = "#{request_label} details"
    errors.add(:message, "#{label} can't be blank")
  end

  def request_received_on_required_for_assisted_request
    return unless assisted_request_requested?
    return if request_received_on.present?

    errors.add(:request_received_on, "Select the complaint or suggestion date for this oral ticket.")
  end

  def request_received_time_required_for_assisted_request
    return unless assisted_request_requested?
    return if request_received_time.present?

    errors.add(:request_received_time, "Select the complaint or suggestion time for this oral ticket.")
  end

  def request_received_on_cannot_be_in_future
    return if request_received_on.blank?

    parsed_date = Date.iso8601(request_received_on.to_s)
    return unless parsed_date > display_time_zone.today

    errors.add(:request_received_on, "can't be in the future")
  rescue ArgumentError
    nil
  end

  def question_subject_presence_for_selected_type
    return if request_type.blank?
    return if question_subject.present?

    errors.add(:question_subject, "Select a common question or type your own topic.")
  end

  def question_master_matches_request_context
    return if help_desk_question_master.blank?

    if department_id.present? && help_desk_question_master.department_id != department_id
      errors.add(:help_desk_question_master_id, "must belong to the selected department")
    end

    if request_type.present? && help_desk_question_master.request_type != request_type
      errors.add(:help_desk_question_master_id, "must match the selected request type")
    end

    return if help_desk_question_master.active?

    errors.add(:help_desk_question_master_id, "is not available for selection")
  end

  def documents_are_allowed
    validate_attachment_set(documents, "documents")
    validate_attachment_set(support_documents, "support attachments")
    validate_attachment_set(requester_followup_documents, "reopen attachments")
  end

  def validate_attachment_set(attachment_set, label)
    return unless attachment_set.attached?

    if attachment_set.attachments.size > MAX_DOCUMENTS
      errors.add(:documents, "#{label} allow a maximum of #{MAX_DOCUMENTS} files")
    end

    attachment_set.each do |document|
      next unless document.blob.present?

      if document.blob.byte_size > MAX_DOCUMENT_SIZE
        errors.add(:documents, "#{document.filename} is larger than 10MB")
      end
    end
  end

  def attach_documents_to(attachment_name, files)
    files = Array(files).reject(&:blank?)
    return if files.blank?

    public_send(attachment_name).attach(files)
  end

  def ensure_legacy_support_update!
    return if new_record?
    return if response_message.blank?
    return if support_updates.exists?

    record_support_update!(
      reviewer: responded_by_user,
      message: response_message,
      created_at: responded_at.presence || updated_at.presence || Time.current
    )
  end

  def record_initial_support_update
    return if response_message.blank?
    return if support_updates.exists?

    record_support_update!(
      reviewer: responded_by_user,
      message: response_message,
      created_at: responded_at.presence || created_at
    )
  end

  def record_support_update!(reviewer:, message:, created_at:)
    support_updates.create!(
      user: reviewer,
      message: message,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def ensure_legacy_requester_remark!
    return if new_record?
    return if requester_remark.blank?
    return if requester_remarks.exists?

    record_requester_remark!(
      actor: approval_pending_user,
      message: requester_remark,
      created_at: updated_at.presence || Time.current
    )
  end

  def record_requester_remark!(actor:, message:, created_at:)
    requester_remarks.create!(
      user: actor,
      message: message,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def department_has_escalation_matrix
    return unless department.present?
    return if assisted_request?
    return if configured_escalation_levels.any?

    errors.add(:department_id, "does not have a configured helpdesk escalation matrix")
  end

  def response_message_required_for_resolution
    return unless status == "resolved"
    return if response_message.present?

    errors.add(:response_message, "can't be blank")
  end

  def approval_user_presence_for_confirmation
    return unless status == "resolved"
    return if approval_user_id.present?

    errors.add(:approval_user, "must be selected before sending this ticket for user action")
  end

  def final_action_mode_presence_for_confirmation
    return unless status == "resolved"
    return if FINAL_ACTION_MODES.include?(final_action_mode)

    errors.add(:final_action_mode, "must be selected before sending this ticket for user action")
  end

  def schedule_initial_escalation_check
    schedule_next_escalation_check!
  end

  def assisted_request_requested?
    ActiveModel::Type::Boolean.new.cast(on_behalf_requested)
  end

  def display_time_zone
    ActiveSupport::TimeZone[DISPLAY_TIME_ZONE] || Time.zone
  end

  def send_assignment_notifications
    return if assigned_to_user.blank? || assigned_to_user.email.blank?

    HelpDeskTicketMailer.ticket_assigned(id).deliver_later
  end

  def send_assignment_notifications_for_reassignment
    return if resolved? || closed?
    return unless saved_change_to_assigned_to_user_id? || saved_change_to_current_escalation_position? || (saved_change_to_status? && reopened?)
    return if assigned_to_user.blank? || assigned_to_user.email.blank?

    HelpDeskTicketMailer.ticket_assigned(id).deliver_later
  end

  def send_resolution_notifications
    return unless saved_change_to_status? && resolved?

    recipients = [ requester_email, submitted_by_user&.email ].compact.map(&:strip).reject(&:blank?).uniq
    return if recipients.blank?

    HelpDeskTicketMailer.ticket_resolved(id, recipients).deliver_later
  end
end
