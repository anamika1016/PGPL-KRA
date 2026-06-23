class AddBookingBasisToGuestHouseBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :guest_house_bookings, :booking_for, :string, null: false, default: "self"
    add_index :guest_house_bookings, :booking_for
  end
end
