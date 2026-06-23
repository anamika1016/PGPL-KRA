class CreateGuestHouseWaitlists < ActiveRecord::Migration[7.1]
  def change
    create_table :guest_house_waitlists do |t|
      t.references :user, null: false, foreign_key: true
      t.references :guest_house, null: false, foreign_key: true
      t.date :booking_date, null: false
      t.time :checkin_time, null: false
      t.date :checkout_date, null: false
      t.time :checkout_time, null: false
      t.integer :rooms_count, null: false
      t.string :room_type, null: false
      t.string :guest_gender, null: false
      t.string :booking_for, null: false
      t.jsonb :occupant_gender_counts, default: {}, null: false
      t.string :status, default: "waiting", null: false
      t.datetime :notified_at
      t.datetime :fulfilled_at
      t.timestamps
    end

    add_index :guest_house_waitlists,
              [ :user_id, :guest_house_id, :booking_date, :checkin_time, :checkout_date, :checkout_time, :room_type, :booking_for ],
              name: "index_gh_waitlists_on_request"
    add_index :guest_house_waitlists, [ :guest_house_id, :status, :booking_date ], name: "index_gh_waitlists_on_house_status_date"
    add_check_constraint :guest_house_waitlists, "status IN ('waiting', 'notified', 'fulfilled', 'expired')", name: "gh_waitlists_status_valid"

    add_reference :guest_house_notifications, :guest_house_waitlist, foreign_key: true
  end
end
