class AddIndividualBillingToGuestHouseBookingGuests < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_booking_guests, :room_charge_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_booking_guests, :other_services_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_booking_guests, :other_services_details, :text
    add_column :guest_house_booking_guests, :gst_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_booking_guests, :total_bill_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_booking_guests, :bill_note, :text
    add_column :guest_house_booking_guests, :billed_at, :datetime

    add_check_constraint :guest_house_booking_guests,
                         "room_charge_amount >= 0 AND other_services_amount >= 0 AND gst_amount >= 0 AND total_bill_amount >= 0",
                         name: "gh_booking_guests_bill_amounts_non_negative"
  end
end
