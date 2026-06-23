class AddStayWorkflowToGuestHouseBookingGuests < ActiveRecord::Migration[8.0]
  def up
    add_column :guest_house_booking_guests, :checkin_date, :date
    add_column :guest_house_booking_guests, :checkin_time, :time
    add_column :guest_house_booking_guests, :checkout_date, :date
    add_column :guest_house_booking_guests, :checkout_time, :time
    add_column :guest_house_booking_guests, :stay_status, :string, null: false, default: "pending"
    add_column :guest_house_booking_guests, :checked_in_at, :datetime
    add_column :guest_house_booking_guests, :checked_out_at, :datetime
    add_column :guest_house_booking_guests, :id_proof_type, :string
    add_column :guest_house_booking_guests, :id_proof_number, :string
    add_column :guest_house_booking_guests, :checkin_remark, :text
    add_column :guest_house_booking_guests, :checkout_remark, :text

    execute <<~SQL.squish
      UPDATE guest_house_booking_guests AS guests
      SET checkin_date = bookings.booking_date,
          checkin_time = bookings.checkin_time,
          checkout_date = COALESCE(bookings.extended_checkout_date, bookings.checkout_date),
          checkout_time = COALESCE(bookings.extended_checkout_time, bookings.checkout_time),
          stay_status = CASE
            WHEN bookings.status = 'checked_out' THEN 'checked_out'
            WHEN bookings.status = 'checked_in' THEN 'checked_in'
            ELSE 'pending'
          END,
          checked_in_at = bookings.checked_in_at,
          checked_out_at = bookings.checked_out_at
      FROM guest_house_bookings AS bookings
      WHERE bookings.id = guests.guest_house_booking_id
    SQL

    change_column_null :guest_house_booking_guests, :checkin_date, false
    change_column_null :guest_house_booking_guests, :checkin_time, false
    change_column_null :guest_house_booking_guests, :checkout_date, false
    change_column_null :guest_house_booking_guests, :checkout_time, false

    add_index :guest_house_booking_guests, [ :guest_house_booking_id, :stay_status ],
              name: "index_gh_booking_guests_on_booking_status"
    add_check_constraint :guest_house_booking_guests,
                         "stay_status IN ('pending', 'checked_in', 'checked_out')",
                         name: "gh_booking_guests_stay_status_valid"
  end

  def down
    remove_check_constraint :guest_house_booking_guests, name: "gh_booking_guests_stay_status_valid"
    remove_index :guest_house_booking_guests, name: "index_gh_booking_guests_on_booking_status"
    remove_columns :guest_house_booking_guests,
                   :checkin_date, :checkin_time, :checkout_date, :checkout_time,
                   :stay_status, :checked_in_at, :checked_out_at,
                   :id_proof_type, :id_proof_number, :checkin_remark, :checkout_remark
  end
end
