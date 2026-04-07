class CreateAchievementRemarks < ActiveRecord::Migration[8.0]
  def change
    create_table :achievement_remarks do |t|
      t.text :l1_remarks
      t.float :l1_percentage
      t.text :l2_remarks
      t.float :l2_percentage

      t.timestamps
    end
  end
end
