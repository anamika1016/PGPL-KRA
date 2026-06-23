class GuestHouseBookingGuest < ApplicationRecord
  GENDERS = %w[male female other].freeze
  STAY_STATUSES = %w[pending checked_in checked_out].freeze
  PAYMENT_STATUSES = %w[pending generated uploaded paid waived].freeze
  APPROVAL_STATUSES = %w[pending accepted rejected].freeze

  belongs_to :guest_house_booking
  belongs_to :accepted_by, class_name: "User", optional: true
  has_one_attached :id_proof
  has_one_attached :payment_receipt
  has_one_attached :payment_qr_image

  before_validation :set_schedule_defaults
  before_validation :normalize_values
  before_validation :ensure_payment_qr_token

  # Keep enum types explicit so a long-running Rails process can load this model
  # immediately after the corresponding columns are added by a migration.
  attribute :stay_status, :string, default: "pending"
  attribute :payment_status, :string, default: "pending"
  attribute :approval_status, :string, default: "pending"
  attribute :payment_receipt_number, :string
  attribute :room_charge_overridden, :boolean, default: false

  validates :first_name, :last_name, :aadhaar_number, :gender, :checkin_date, :checkin_time, :checkout_date, :checkout_time, presence: true
  validates :aadhaar_number, format: { with: /\A\d{12}\z/, message: "must be 12 digits" }
  validates :gender, inclusion: { in: GENDERS }
  validates :stay_status, inclusion: { in: STAY_STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :age, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validate :checkout_after_checkin
  validate :schedule_within_booking_window
  validate :actual_checkout_after_checkin

  enum :stay_status, STAY_STATUSES.index_with(&:itself), prefix: :stay
  enum :payment_status, PAYMENT_STATUSES.index_with(&:itself), prefix: :payment
  enum :approval_status, APPROVAL_STATUSES.index_with(&:itself), prefix: :approval

  def full_name
    [ first_name, last_name ].compact_blank.join(" ")
  end

  def planned_checkin_at
    GuestHouseBooking.slot_datetime(checkin_date, checkin_time)
  end

  def planned_checkout_at
    GuestHouseBooking.slot_datetime(checkout_date, checkout_time)
  end

  def charge_days(as_of: nil)
    billing_end_date = (checked_out_at || as_of)&.to_date || checkout_date
    return 1 if checkin_date.blank? || billing_end_date.blank?

    [ (billing_end_date - checkin_date).to_i, 1 ].max
  end

  def room_charge_total
    guest_house_booking.guest_house.room_charge_per_day.to_d * charge_days
  end

  def billed?
    billed_at.present?
  end

  def calculate_bill!(room_charge_amount: nil)
    self.room_charge_amount = room_charge_amount.nil? ? room_charge_total : room_charge_amount.to_d
    self.other_services_amount = other_services_amount.to_d
    self.gst_amount = ((self.room_charge_amount.to_d + self.other_services_amount) * 0.05).round(2)
    self.total_bill_amount = self.room_charge_amount + self.other_services_amount + self.gst_amount
    self.billed_at = Time.current
    self.payment_status = "generated" if payment_pending?
  end

  def payment_complete?
    payment_paid? || payment_waived?
  end

  def active_occupant?
    !approval_rejected?
  end

  def payment_qr_payload
    [
      "Guest House Individual Payment",
      "Ref: #{guest_house_booking.booking_reference_label}",
      "Occupant: #{full_name}",
      "Guest House: #{guest_house_booking.guest_house.name}",
      "Bill: #{format('%.2f', total_bill_amount)}",
      "Token: #{payment_qr_token}",
      "Status: #{payment_status.humanize}"
    ].join("\n")
  end

  def ensure_payment_receipt_number!
    self.payment_receipt_number ||= "GHR-G-#{id.to_s.rjust(6, '0')}"
  end

  private

  def set_schedule_defaults
    return if guest_house_booking.blank?

    self.checkin_date ||= guest_house_booking.booking_date
    self.checkin_time ||= guest_house_booking.checkin_time
    self.checkout_date ||= guest_house_booking.effective_checkout_date
    self.checkout_time ||= guest_house_booking.effective_checkout_time
    self.stay_status = "pending" if stay_status.blank?
  end

  def normalize_values
    self.first_name = first_name.to_s.strip
    self.last_name = last_name.to_s.strip
    self.aadhaar_number = aadhaar_number.to_s.gsub(/\D/, "")
    self.mobile_number = mobile_number.to_s.gsub(/\D/, "").presence
    self.email = email.to_s.strip.downcase.presence
    self.gender = gender.to_s.downcase.presence
    self.organization = organization.to_s.strip.presence
    self.designation = designation.to_s.strip.presence
    self.purpose = purpose.to_s.strip.presence
  end

  def ensure_payment_qr_token
    self.payment_qr_token ||= SecureRandom.urlsafe_base64(12)
  end

  def checkout_after_checkin
    return if planned_checkin_at.blank? || planned_checkout_at.blank?

    errors.add(:checkout_time, "must be after individual check-in date/time") unless planned_checkout_at > planned_checkin_at
  end

  def schedule_within_booking_window
    return if guest_house_booking.blank? || planned_checkin_at.blank? || planned_checkout_at.blank?
    return if guest_house_booking.checkin_at_value.blank? || guest_house_booking.effective_checkout_at_value.blank?

    if planned_checkin_at < guest_house_booking.checkin_at_value || planned_checkout_at > guest_house_booking.effective_checkout_at_value
      errors.add(:base, "#{full_name.presence || 'Occupant'} schedule must stay within the overall booking window")
    end
  end

  def actual_checkout_after_checkin
    return if checked_out_at.blank?

    actual_start = checked_in_at || planned_checkin_at
    errors.add(:checked_out_at, "must be after check-in") if actual_start.present? && checked_out_at < actual_start
  end
end
