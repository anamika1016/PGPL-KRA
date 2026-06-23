class CreateGuestHouseNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :guest_house_notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :guest_house_booking, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.string :title, null: false
      t.text :message, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :guest_house_notifications, [ :user_id, :read_at, :created_at ],
              name: "index_gh_notifications_on_user_read_created"
  end
end
