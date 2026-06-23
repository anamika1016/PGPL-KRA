class AddIndividualPaymentToGuestHouseBookingGuests < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_booking_guests, :payment_status, :string, default: "pending", null: false
    add_column :guest_house_booking_guests, :transaction_id, :string
    add_column :guest_house_booking_guests, :payment_details, :text
    add_column :guest_house_booking_guests, :payment_qr_token, :string
    add_column :guest_house_booking_guests, :paid_at, :datetime

    add_index :guest_house_booking_guests, :payment_status
    add_check_constraint :guest_house_booking_guests,
                         "payment_status IN ('pending', 'generated', 'uploaded', 'paid', 'waived')",
                         name: "gh_booking_guests_payment_status_valid"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE guest_house_booking_guests
          SET payment_status = 'generated'
          WHERE billed_at IS NOT NULL
        SQL
      end
    end
  end
end
