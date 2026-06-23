class RemoveDefaultGuestGenderFromGuestHouseBookings < ActiveRecord::Migration[7.1]
  def change
    change_column_default :guest_house_bookings, :guest_gender, from: "male", to: nil
    change_column_null :guest_house_bookings, :guest_gender, true
  end
end
