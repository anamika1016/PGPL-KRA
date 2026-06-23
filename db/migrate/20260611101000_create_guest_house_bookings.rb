class CreateGuestHouseBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_house_bookings do |t|
      t.references :guest_house, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.string :booking_reference, null: false
      t.date :booking_date, null: false
      t.time :checkin_time, null: false
      t.time :checkout_time, null: false
      t.integer :rooms_count, null: false, default: 1
      t.string :status, null: false, default: "pending"
      t.text :admin_remark
      t.datetime :accepted_at
      t.datetime :checked_in_at
      t.datetime :checked_out_at
      t.date :extended_checkout_date
      t.time :extended_checkout_time
      t.decimal :bill_amount, precision: 10, scale: 2
      t.string :payment_status, null: false, default: "pending"
      t.text :payment_note
      t.string :payment_qr_token

      t.timestamps
    end

    add_index :guest_house_bookings, :booking_reference, unique: true
    add_index :guest_house_bookings, [ :guest_house_id, :booking_date, :status ], name: "index_gh_bookings_on_house_date_status"
    add_check_constraint :guest_house_bookings, "rooms_count > 0", name: "guest_house_bookings_rooms_positive"
  end
end
