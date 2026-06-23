class CreateGuestHouseFacilities < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_house_facilities do |t|
      t.references :guest_house, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :rate, precision: 10, scale: 2, default: 0, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :guest_house_facilities, [ :guest_house_id, :name ], unique: true
    add_check_constraint :guest_house_facilities, "rate >= 0", name: "guest_house_facilities_rate_non_negative"
  end
end
