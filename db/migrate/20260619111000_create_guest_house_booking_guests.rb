class CreateGuestHouseBookingGuests < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_house_booking_guests do |t|
      t.references :guest_house_booking, null: false, foreign_key: true, index: { name: "index_gh_booking_guests_on_booking_id" }
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :aadhaar_number, null: false
      t.string :mobile_number
      t.string :email
      t.string :gender
      t.integer :age
      t.string :organization
      t.string :designation
      t.text :purpose

      t.timestamps
    end

    add_index :guest_house_booking_guests, :aadhaar_number
    add_check_constraint :guest_house_booking_guests, "age IS NULL OR age > 0", name: "gh_booking_guests_age_positive"
  end
end
