class CreateActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :activities do |t|
      t.references :department, null: false, foreign_key: true
      t.integer :activity_id
      t.string :activity_name
      t.string :unit
      t.float :weight

      t.timestamps
    end
  end
end
