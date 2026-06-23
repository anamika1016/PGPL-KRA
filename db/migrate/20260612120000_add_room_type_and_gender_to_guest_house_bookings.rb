class AddRoomTypeAndGenderToGuestHouseBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :guest_house_bookings, :room_type, :string, null: false, default: "sharing"
    add_column :guest_house_bookings, :guest_gender, :string, null: false, default: "male"

    add_index :guest_house_bookings, [ :guest_house_id, :booking_date, :checkout_date, :status, :room_type, :guest_gender ],
              name: "index_gh_bookings_on_room_allocation"
  end
end
