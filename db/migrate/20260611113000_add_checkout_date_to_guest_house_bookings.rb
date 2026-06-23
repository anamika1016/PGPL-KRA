class AddCheckoutDateToGuestHouseBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :guest_house_bookings, :checkout_date, :date

    reversible do |dir|
      dir.up do
        execute "UPDATE guest_house_bookings SET checkout_date = booking_date WHERE checkout_date IS NULL"
      end
    end

    change_column_null :guest_house_bookings, :checkout_date, false
    add_index :guest_house_bookings,
              [ :guest_house_id, :booking_date, :checkout_date, :status ],
              name: "index_gh_bookings_on_house_date_range_status"
  end
end
