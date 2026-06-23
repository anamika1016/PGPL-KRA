class CreateGuestHouses < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_houses do |t|
      t.string :name, null: false
      t.integer :total_rooms, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.references :manager_user, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :guest_houses, "lower(name)", unique: true, name: "index_guest_houses_on_lower_name"
    add_check_constraint :guest_houses, "total_rooms > 0", name: "guest_houses_total_rooms_positive"
  end
end
