class GuestHouseWaitlist < ApplicationRecord
  STATUSES = %w[waiting notified fulfilled expired].freeze

  belongs_to :user
  belongs_to :guest_house
  has_many :guest_house_notifications, dependent: :nullify

  enum :status, STATUSES.index_with(&:itself)

  validates :booking_date, :checkin_time, :checkout_date, :checkout_time, :rooms_count, :room_type, :guest_gender, :booking_for, presence: true

  scope :actionable, -> { where(status: %w[waiting notified]).where("checkout_date >= ?", Date.current) }

  def self.capture!(booking)
    attributes = {
      user: booking.user,
      guest_house: booking.guest_house,
      booking_date: booking.booking_date,
      checkin_time: booking.checkin_time,
      checkout_date: booking.effective_checkout_date,
      checkout_time: booking.effective_checkout_time,
      rooms_count: booking.rooms_count,
      room_type: booking.room_type,
      guest_gender: booking.guest_gender,
      booking_for: booking.booking_for,
      occupant_gender_counts: booking.external_booking? ? booking.occupant_counts_by_gender : {}
    }
    request = actionable.find_or_initialize_by(attributes.except(:rooms_count, :guest_gender, :occupant_gender_counts))
    request.assign_attributes(attributes.merge(status: "waiting", notified_at: nil))
    request.save!
    request
  end

  def self.notify_available_for!(cancelled_booking, actor:)
    actionable.where(guest_house_id: cancelled_booking.guest_house_id).find_each do |request|
      next unless request.available_now?
      next if request.guest_house_notifications.where(event_type: "availability_opened").exists?

      request.update!(status: "notified", notified_at: Time.current)
      GuestHouseNotificationService.availability_opened(request, cancelled_booking: cancelled_booking, actor: actor)
    end
  end

  def self.fulfill_matching!(booking)
    actionable.where(
      user_id: booking.user_id,
      guest_house_id: booking.guest_house_id,
      booking_date: booking.booking_date,
      checkout_date: booking.effective_checkout_date,
      room_type: booking.room_type,
      booking_for: booking.booking_for
    ).update_all(status: "fulfilled", fulfilled_at: Time.current, updated_at: Time.current)
  end

  def available_now?
    candidate.available_rooms_for_slot >= 0
  end

  def alternative_dates(limit: 3)
    candidate.alternate_dates(limit: limit)
  end

  private

  def candidate
    booking = user.guest_house_bookings.new(
      guest_house: guest_house,
      booking_date: booking_date,
      checkin_time: checkin_time,
      checkout_date: checkout_date,
      checkout_time: checkout_time,
      rooms_count: rooms_count,
      room_type: room_type,
      guest_gender: guest_gender,
      booking_for: booking_for,
      status: "confirmed"
    )
    if booking.external_booking?
      occupant_gender_counts.each do |gender, count|
        count.to_i.times { booking.guest_house_booking_guests.build(gender: gender) }
      end
    end
    booking
  end
end
