class CreateAchievements < ActiveRecord::Migration[8.0]
  def change
    create_table :achievements do |t|
      t.references :user_detail, null: false, foreign_key: true
      t.string :month
      t.string :achievement

      t.timestamps
    end
  end
end
