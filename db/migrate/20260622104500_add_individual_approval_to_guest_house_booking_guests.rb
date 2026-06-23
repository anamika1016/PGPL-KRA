class AddIndividualApprovalToGuestHouseBookingGuests < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_booking_guests, :approval_status, :string, default: "pending", null: false
    add_column :guest_house_booking_guests, :accepted_by_id, :bigint
    add_column :guest_house_booking_guests, :accepted_at, :datetime
    add_column :guest_house_booking_guests, :approval_remark, :text
    add_column :guest_house_booking_guests, :rejection_remark, :text

    add_index :guest_house_booking_guests, :approval_status
    add_index :guest_house_booking_guests, :accepted_by_id
    add_foreign_key :guest_house_booking_guests, :users, column: :accepted_by_id
    add_check_constraint :guest_house_booking_guests,
                         "approval_status IN ('pending', 'accepted', 'rejected')",
                         name: "gh_booking_guests_approval_status_valid"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE guest_house_booking_guests AS guests
          SET approval_status = CASE
                WHEN bookings.status IN ('accepted', 'checked_in', 'checked_out') THEN 'accepted'
                WHEN bookings.status = 'rejected' THEN 'rejected'
                ELSE 'pending'
              END,
              accepted_by_id = CASE WHEN bookings.status IN ('accepted', 'checked_in', 'checked_out') THEN bookings.accepted_by_id END,
              accepted_at = CASE WHEN bookings.status IN ('accepted', 'checked_in', 'checked_out') THEN bookings.accepted_at END
          FROM guest_house_bookings AS bookings
          WHERE bookings.id = guests.guest_house_booking_id
        SQL
      end
    end
  end
end
