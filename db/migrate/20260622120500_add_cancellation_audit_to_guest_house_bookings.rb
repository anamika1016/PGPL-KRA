class AddCancellationAuditToGuestHouseBookings < ActiveRecord::Migration[7.1]
  def change
    add_column :guest_house_bookings, :cancellation_reason, :text
    add_column :guest_house_bookings, :cancelled_at, :datetime
    add_column :guest_house_bookings, :cancelled_by_id, :bigint

    add_index :guest_house_bookings, :cancelled_by_id
    add_foreign_key :guest_house_bookings, :users, column: :cancelled_by_id
  end
end
