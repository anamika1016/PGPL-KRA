class TrackGuestHouseRoomChargeOverrides < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_bookings, :room_charge_overridden, :boolean, default: false, null: false
    add_column :guest_house_booking_guests, :room_charge_overridden, :boolean, default: false, null: false
  end
end
