class ExpandGuestHouseWorkflow < ActiveRecord::Migration[8.0]
  def change
    add_column :guest_houses, :room_charge_per_day, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_houses, :facility_rates, :text

    add_column :guest_house_bookings, :rejection_remark, :text
    add_column :guest_house_bookings, :id_proof_type, :string
    add_column :guest_house_bookings, :id_proof_number, :string
    add_column :guest_house_bookings, :checkin_remark, :text
    add_column :guest_house_bookings, :guest_complaint, :text
    add_column :guest_house_bookings, :complaint_submitted_at, :datetime
    add_column :guest_house_bookings, :complaint_status, :string, default: "open", null: false
    add_column :guest_house_bookings, :room_charge_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_bookings, :other_services_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_bookings, :other_services_details, :text
    add_column :guest_house_bookings, :gst_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_bookings, :total_bill_amount, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :guest_house_bookings, :transaction_id, :string
    add_column :guest_house_bookings, :payment_details, :text
    add_column :guest_house_bookings, :admin_reminder_sent_at, :datetime
    add_column :guest_house_bookings, :checkin_sms_sent_at, :datetime

    add_check_constraint :guest_houses,
                         "room_charge_per_day >= 0",
                         name: "guest_houses_room_charge_non_negative"
    add_check_constraint :guest_house_bookings,
                         "room_charge_amount >= 0 AND other_services_amount >= 0 AND gst_amount >= 0 AND total_bill_amount >= 0",
                         name: "guest_house_booking_amounts_non_negative"
  end
end
