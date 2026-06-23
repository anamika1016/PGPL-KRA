class AddGeneratedReceiptFieldsToGuestHousePayments < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_bookings, :payment_receipt_number, :string
    add_column :guest_house_bookings, :paid_at, :datetime
    add_index :guest_house_bookings, :payment_receipt_number, unique: true

    add_column :guest_house_booking_guests, :payment_receipt_number, :string
    add_index :guest_house_booking_guests, :payment_receipt_number, unique: true
  end
end
