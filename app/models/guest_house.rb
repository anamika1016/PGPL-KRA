class GuestHouse < ApplicationRecord
  has_many :guest_house_waitlists, dependent: :destroy
  belongs_to :manager_user, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :guest_house_bookings, dependent: :restrict_with_error
  has_many :guest_house_facilities, dependent: :destroy

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :total_rooms, numericality: { only_integer: true, greater_than: 0 }
  validates :room_charge_per_day, numericality: { greater_than_or_equal_to: 0 }
  validate :total_rooms_not_below_active_allocations

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(Arel.sql("lower(name) asc")) }
  scope :managed_by, ->(user) { where(manager_user_id: user.id) }

  def display_name
    "#{name} (#{total_rooms} rooms, Rs. #{format('%.2f', room_charge_per_day || 0)}/bed/day)"
  end

  def facility_rate_lines
    facility_rates.to_s.lines.map(&:strip).reject(&:blank?)
  end

  private

  def normalize_name
    self.name = name.to_s.strip.squeeze(" ")
  end

  def total_rooms_not_below_active_allocations
    return unless persisted? && will_save_change_to_total_rooms? && total_rooms.to_i.positive?

    active_bookings = GuestHouseBooking.active_for_availability
                                        .includes(:guest_house_booking_guests)
                                        .where(guest_house_id: id)
                                        .to_a
    peak_rooms = active_bookings.filter_map do |candidate|
      next if candidate.checkin_at_value.blank? || candidate.availability_checkout_at_value.blank?

      occupancy_at = candidate.checkin_at_value
      overlapping = active_bookings.select do |booking|
        booking.checkin_at_value <= occupancy_at && booking.availability_checkout_at_value > occupancy_at
      end
      GuestHouseBooking.room_units_required(overlapping)
    end.max.to_i

    if total_rooms.to_i < peak_rooms
      errors.add(:total_rooms, "cannot be less than #{peak_rooms} rooms already allocated to active bookings")
    end
  end
end
