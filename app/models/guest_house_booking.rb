class GuestHouseBooking < ApplicationRecord
  STATUSES = %w[pending confirmed accepted checked_in checked_out rejected cancelled].freeze
  ACTIVE_ROOM_STATUSES = %w[pending confirmed accepted checked_in].freeze
  PAYMENT_STATUSES = %w[pending generated uploaded paid waived].freeze
  ROOM_TYPES = %w[single sharing].freeze
  GUEST_GENDERS = %w[male female other].freeze
  BOOKING_FOR_OPTIONS = %w[self guest auditor].freeze
  DISPLAY_TIME_ZONE = "Asia/Kolkata".freeze
  SINGLE_ROOM_DESIGNATION_PATTERN = /\b(md|m\.d\.|director|ceo|chief executive officer|managing director)\b/i

  belongs_to :guest_house
  belongs_to :user
  belongs_to :accepted_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  has_many :guest_house_booking_guests, dependent: :destroy
  has_many :guest_house_notifications, dependent: :destroy
  has_one_attached :payment_receipt
  has_one_attached :id_proof
  has_one_attached :payment_qr_image
  accepts_nested_attributes_for :guest_house_booking_guests, allow_destroy: true, reject_if: :guest_detail_blank?

  # Explicit types allow a long-running development process to use the fields
  # immediately after the cancellation migration without stale schema errors.
  attribute :cancellation_reason, :string
  attribute :cancelled_at, :datetime
  attribute :cancelled_by_id, :integer
  attribute :payment_receipt_number, :string
  attribute :paid_at, :datetime
  attribute :room_charge_overridden, :boolean, default: false

  before_validation :normalize_counts
  before_validation :normalize_booking_for
  before_validation :normalize_room_preferences
  before_validation :set_default_checkout_date
  before_validation :ensure_booking_reference, on: :create
  before_validation :ensure_payment_qr_token
  before_validation :set_default_statuses
  validates :room_type, inclusion: { in: ROOM_TYPES }
  validates :guest_gender, inclusion: { in: GUEST_GENDERS }, allow_nil: true
  validates :guest_gender, presence: true, if: :self_booking?
  validates :booking_for, inclusion: { in: BOOKING_FOR_OPTIONS }
  validates :booking_date, :checkout_date, :checkin_time, :checkout_time, presence: true
  validates :rooms_count, numericality: { only_integer: true, greater_than: 0 }
  validates :feedback_rating, inclusion: { in: 1..5 }, allow_nil: true
  validates :feedback_comment, length: { maximum: 1000 }, allow_blank: true
  validate :checkout_after_checkin
  validate :extended_checkout_after_original
  validate :actual_checkout_after_checkin
  validate :rooms_do_not_exceed_guest_house
  validate :guest_house_must_be_active, on: :create
  validate :booking_date_cannot_be_in_past, on: :create
  validate :room_type_matches_designation
  validate :guest_details_match_booking_basis
  validate :rooms_available_for_slot, if: :availability_validation_required?

  after_commit :notify_booking_created, on: :create
  after_commit :notify_booking_accepted, if: :saved_change_to_status_to_accepted?
  after_commit :notify_checkin, if: :saved_change_to_status_to_checked_in?

  enum :status, STATUSES.index_with(&:itself)
  enum :payment_status, PAYMENT_STATUSES.index_with(&:itself), prefix: :payment

  scope :recent_first, -> { order(created_at: :desc) }
  scope :submitted_by, ->(user) { where(user_id: user.id) }
  scope :for_admin, ->(user) { user.hod? ? all : joins(:guest_house).where(guest_houses: { manager_user_id: user.id }) }
  scope :active_for_availability, -> { where(status: ACTIVE_ROOM_STATUSES) }

  def self.overlapping(guest_house_id:, booking_date:, checkout_date:, checkin_time:, checkout_time:)
    requested_start = slot_datetime(booking_date, checkin_time)
    requested_end = slot_datetime(checkout_date, checkout_time)
    return [] if requested_start.blank? || requested_end.blank?

    active_for_availability
      .includes(:guest_house_booking_guests)
      .where(guest_house_id: guest_house_id)
      .where("booking_date <= ? AND (status = ? OR COALESCE(extended_checkout_date, checkout_date) >= ?)", checkout_date, "checked_in", booking_date)
      .select do |booking|
        booking.checkin_at_value < requested_end && booking.availability_checkout_at_value > requested_start
      end
  end

  def self.room_units_required(bookings)
    single_rooms = bookings.select(&:single?).sum do |booking|
      booking.external_booking? ? booking.availability_occupant_counts_by_gender.values.sum : booking.rooms_count
    end
    sharing_occupants_by_gender = bookings.select(&:sharing?).each_with_object(Hash.new(0)) do |booking, counts|
      booking.availability_occupant_counts_by_gender.each { |gender, occupant_count| counts[gender] += occupant_count }
    end
    sharing_rooms = sharing_occupants_by_gender.values.sum { |occupant_count| (occupant_count / 2.0).ceil }

    single_rooms + sharing_rooms
  end

  def available_rooms_for_slot
    guest_house.total_rooms - rooms_required_for(overlapping_bookings_for_slot)
  end

  def overlapping_bookings_for_slot
    self.class.overlapping(
      guest_house_id: guest_house_id,
      booking_date: booking_date,
      checkout_date: effective_checkout_date,
      checkin_time: checkin_time,
      checkout_time: effective_checkout_time
    ).reject { |booking| booking.id == id }
  end

  def availability_error_message(include_alternates: new_record?)
    overlapping_bookings = overlapping_bookings_for_slot
    occupied_rooms = self.class.room_units_required(overlapping_bookings)
    total_required_rooms = rooms_required_for(overlapping_bookings)
    additional_rooms_needed = total_required_rooms - occupied_rooms
    physically_available_rooms = [ guest_house.total_rooms - occupied_rooms, 0 ].max

    message = if physically_available_rooms.zero?
                if single?
                  "No single room is available for the selected date and time"
                elsif occupant_counts_by_gender.one?
                  gender = occupant_counts_by_gender.keys.first.to_s.humanize.downcase
                  "No #{gender} sharing bed is available for the selected date and time"
                else
                  "No gender-compatible sharing beds are available for the selected date and time"
                end
              else
                available_label = physically_available_rooms == 1 ? "room is" : "rooms are"
                needed_label = additional_rooms_needed == 1 ? "room" : "rooms"
                "Only #{physically_available_rooms} #{available_label} available, but this booking needs #{additional_rooms_needed} additional #{needed_label}"
              end

    dates = include_alternates ? alternate_dates.map { |date| date.strftime("%d %b %Y") }.to_sentence : nil
    dates.present? ? "#{message}. Available alternate dates: #{dates}." : "#{message}."
  end

  def alternate_dates(limit: 3)
    return [] if guest_house.blank? || booking_date.blank? || checkout_date.blank? || checkin_time.blank? || checkout_time.blank?

    stay_days = (checkout_date - booking_date).to_i

    (1..14).filter_map do |offset|
      candidate_date = booking_date + offset.days
      candidate_checkout_date = candidate_date + stay_days.days
      overlapping_bookings = self.class.overlapping(
        guest_house_id: guest_house_id,
        booking_date: candidate_date,
        checkout_date: candidate_checkout_date,
        checkin_time: checkin_time,
        checkout_time: checkout_time
      )
      candidate_date if guest_house.total_rooms - rooms_required_for(overlapping_bookings) >= 0
    end.first(limit)
  end

  def booking_reference_label
    booking_reference.presence || "GH-PENDING"
  end

  def requester_name
    user&.display_name || user&.email
  end

  def booking_for_label
    booking_for.to_s.humanize
  end

  def self_booking?
    booking_for == "self"
  end

  def external_booking?
    booking_for.in?(%w[guest auditor])
  end

  def feedback_submitted?
    feedback_rating.present?
  end

  def cancellable?
    (confirmed? || accepted?) && checked_in_at.blank? && active_booking_guests.none?(&:stay_checked_in?)
  end

  def requester_mobile
    user&.mapped_employee_detail&.mobile_number
  end

  def requester_designation
    detail = user&.mapped_employee_detail
    detail&.post.presence || detail&.position.presence || user&.role.to_s
  end

  def single_room_eligible?
    return requester_designation.to_s.match?(SINGLE_ROOM_DESIGNATION_PATTERN) if self_booking?

    occupants = active_booking_guests
    occupants.size == rooms_count.to_i && occupants.present? &&
      occupants.all? { |occupant| occupant.designation.to_s.match?(SINGLE_ROOM_DESIGNATION_PATTERN) }
  end

  def room_type_label
    room_type.to_s.humanize
  end

  def guest_gender_label
    return guest_gender.to_s.humanize unless external_booking?

    occupant_genders = occupant_counts_by_gender.keys
    occupant_genders.presence&.map(&:humanize)&.to_sentence || guest_gender.to_s.humanize
  end

  def checkin_label
    checkin_time&.strftime("%I:%M %p")
  end

  def checkout_label
    checkout_time&.strftime("%I:%M %p")
  end

  def effective_checkout_date
    extended_checkout_date.presence || checkout_date
  end

  def effective_checkout_time
    extended_checkout_time.presence || checkout_time
  end

  def checkin_at_value
    self.class.slot_datetime(booking_date, checkin_time)
  end

  def checkout_at_value
    self.class.slot_datetime(checkout_date, checkout_time)
  end

  def effective_checkout_at_value
    self.class.slot_datetime(effective_checkout_date, effective_checkout_time)
  end

  def availability_checkout_at_value
    scheduled_checkout = effective_checkout_at_value
    return scheduled_checkout unless checked_in? && scheduled_checkout.present? && scheduled_checkout <= Time.current

    display_time_zone.local(9999, 12, 31, 23, 59, 59)
  end

  def self.slot_datetime(date, time)
    return if date.blank? || time.blank?

    display_time_zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
  end

  def self.display_time_zone
    ActiveSupport::TimeZone[DISPLAY_TIME_ZONE] || Time.zone
  end

  def display_time_zone
    self.class.display_time_zone
  end

  def payment_qr_payload
    [
      "Guest House Booking",
      "Ref: #{booking_reference_label}",
      "Guest House: #{guest_house&.name}",
      "Guest: #{requester_name}",
      "Bill: #{invoice_total.positive? ? invoice_total : 'Pending'}",
      "Status: #{payment_status.humanize}"
    ].join("\n")
  end

  def stay_days(as_of: nil)
    billing_end_date = (checked_out_at || as_of)&.to_date || effective_checkout_date
    return 1 if booking_date.blank? || billing_end_date.blank?

    [(billing_end_date - booking_date).to_i, 1].max
  end

  def room_charge_total(as_of: nil)
    guest_house.present? ? guest_house.room_charge_per_day.to_d * chargeable_bed_days(as_of: as_of) : 0.to_d
  end

  def allocation_room_units
    return rooms_count.to_i if single?

    occupant_counts_by_gender.values.sum { |occupant_count| (occupant_count / 2.0).ceil }
  end

  def chargeable_bed_units
    return active_booking_guests.size if external_booking?

    rooms_count.to_i
  end

  def chargeable_bed_days(as_of: nil)
    occupants = active_booking_guests
    return occupants.sum { |occupant| occupant.charge_days(as_of: as_of) } if external_booking? && occupants.present?

    chargeable_bed_units * stay_days(as_of: as_of)
  end

  def occupant_counts_by_gender
    return { guest_gender.to_s => rooms_count.to_i } unless external_booking?

    gender_counts = active_booking_guests.each_with_object(Hash.new(0)) do |guest, counts|
      gender = guest.gender.to_s.downcase
      counts[gender] += 1 if GUEST_GENDERS.include?(gender)
    end

    gender_counts.presence || { guest_gender.to_s => rooms_count.to_i }
  end

  def availability_occupant_counts_by_gender
    return occupant_counts_by_gender unless external_booking?

    occupants = active_booking_guests
    return { guest_gender.to_s => rooms_count.to_i } if occupants.blank?

    occupants.reject(&:stay_checked_out?).each_with_object(Hash.new(0)) do |occupant, counts|
      gender = occupant.gender.to_s.downcase
      counts[gender] += 1 if GUEST_GENDERS.include?(gender)
    end
  end

  def all_occupants_checked_out?
    occupants = active_booking_guests
    external_booking? && occupants.present? && occupants.all?(&:stay_checked_out?)
  end

  def active_booking_guests
    guest_house_booking_guests.reject(&:marked_for_destruction?).select do |guest|
      !guest.respond_to?(:approval_rejected?) || !guest.approval_rejected?
    end
  end

  def sharing?
    room_type == "sharing"
  end

  def single?
    room_type == "single"
  end

  def taxable_amount
    room_charge_amount.to_d + other_services_amount.to_d
  end

  def invoice_total
    total_bill_amount.presence || bill_amount || 0
  end

  def ensure_payment_receipt_number!
    self.payment_receipt_number ||= "GHR-B-#{id.to_s.rjust(6, '0')}"
  end

  def calculate_bill!(room_charge_amount: nil)
    self.room_charge_amount = room_charge_amount.nil? ? room_charge_total : room_charge_amount.to_d
    self.other_services_amount = other_services_amount.to_d
    self.gst_amount = ((self.room_charge_amount.to_d + other_services_amount.to_d) * 0.05).round(2)
    self.total_bill_amount = self.room_charge_amount.to_d + other_services_amount.to_d + gst_amount.to_d
    self.bill_amount = total_bill_amount
    self.payment_status = "generated" if payment_status.blank? || payment_pending?
  end

  private

  def normalize_counts
    self.rooms_count = rooms_count.to_i
  end

  def normalize_booking_for
    self.booking_for = booking_for.to_s.downcase.presence || "self"
    self.booking_for = "self" unless BOOKING_FOR_OPTIONS.include?(booking_for)
  end

  def normalize_room_preferences
    default_room_type = self_booking? && single_room_eligible? ? "single" : "sharing"
    self.room_type = room_type.to_s.downcase.presence || default_room_type
    self.room_type = "sharing" unless ROOM_TYPES.include?(room_type)
    normalized_gender = guest_gender.to_s.downcase.presence
    if self_booking?
      self.guest_gender = normalized_gender
    else
      occupant_gender = guest_house_booking_guests.map { |guest| guest.gender.to_s.downcase }.find { |gender| GUEST_GENDERS.include?(gender) }
      self.guest_gender = occupant_gender || normalized_gender
    end
  end

  def set_default_checkout_date
    self.checkout_date ||= booking_date
  end

  def set_default_statuses
    self.status = "pending" if status.blank?
    self.payment_status = "pending" if payment_status.blank?
  end

  def ensure_booking_reference
    self.booking_reference ||= "GH-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end

  def ensure_payment_qr_token
    self.payment_qr_token ||= SecureRandom.urlsafe_base64(12)
  end

  def checkout_after_checkin
    return if booking_date.blank? || checkout_date.blank? || checkin_time.blank? || checkout_time.blank?

    errors.add(:checkout_time, "must be after check-in date/time") unless checkout_at_value > checkin_at_value
  end

  def extended_checkout_after_original
    return if extended_checkout_date.blank? && extended_checkout_time.blank?
    return if checkout_at_value.blank? || effective_checkout_at_value.blank?

    errors.add(:base, "Extended checkout must be after the original checkout") unless effective_checkout_at_value > checkout_at_value
  end

  def actual_checkout_after_checkin
    actual_checkin = checked_in_at || checkin_at_value
    return if checked_out_at.blank? || actual_checkin.blank?

    errors.add(:checked_out_at, "must be after check-in") if checked_out_at < actual_checkin
  end

  def rooms_do_not_exceed_guest_house
    return if guest_house.blank? || rooms_count.blank?

    if allocation_room_units > guest_house.total_rooms
      errors.add(:base, "This booking needs #{allocation_room_units} rooms based on room type and gender, but #{guest_house.name} has only #{guest_house.total_rooms} rooms.")
    end
  end

  def guest_house_must_be_active
    errors.add(:guest_house, "is not active") if guest_house.present? && !guest_house.active?
  end

  def booking_date_cannot_be_in_past
    errors.add(:booking_date, "cannot be in the past") if booking_date.present? && booking_date < Date.current
  end

  def room_type_matches_designation
    if single_room_eligible?
      errors.add(:room_type, "Director, MD and CEO bookings must use single room") unless single?
    elsif single?
      errors.add(:room_type, "single room is allowed only when every occupant is Director, MD or CEO")
    end
  end

  def guest_details_match_booking_basis
    if self_booking?
      guest_house_booking_guests.each(&:mark_for_destruction)
      return
    end

    active_guest_details = guest_house_booking_guests.reject(&:marked_for_destruction?)
    required_count = rooms_count.to_i

    errors.add(:base, "#{booking_for_label} details are required") if active_guest_details.blank?
    if required_count.positive? && active_guest_details.size != required_count
      errors.add(:base, "Enter details for exactly #{required_count} #{booking_for_label.downcase}(s)")
    end
  end

  def guest_detail_blank?(attributes)
    attributes.except("id", "_destroy").values.all?(&:blank?)
  end

  def rooms_available_for_slot
    return if guest_house.blank? || booking_date.blank? || effective_checkout_date.blank? || checkin_time.blank? || effective_checkout_time.blank?
    return if allocation_room_units > guest_house.total_rooms
    return if available_rooms_for_slot >= 0

    errors.add(:base, :unavailable, message: availability_error_message)
  end

  def availability_validation_required?
    new_record? || will_save_change_to_guest_house_id? || will_save_change_to_booking_date? ||
      will_save_change_to_checkout_date? || will_save_change_to_checkin_time? ||
      will_save_change_to_checkout_time? || will_save_change_to_extended_checkout_date? ||
      will_save_change_to_extended_checkout_time? || will_save_change_to_rooms_count? ||
      will_save_change_to_room_type? || will_save_change_to_guest_gender?
  end

  def rooms_required_for(bookings)
    self.class.room_units_required(bookings + [ self ])
  end

  def saved_change_to_status_to_accepted?
    saved_change_to_status? && accepted?
  end

  def notify_booking_created
    GuestHouseNotificationService.booking_created(self)
  end

  def notify_booking_accepted
    GuestHouseNotificationService.booking_accepted(self)
  end

  def saved_change_to_status_to_checked_in?
    saved_change_to_status? && checked_in?
  end

  def notify_checkin
    GuestHouseNotificationService.checkin_completed(self) if self_booking?
  end
end
