class AddAchievementToAchievementRemarks < ActiveRecord::Migration[8.0]
  def change
    add_reference :achievement_remarks, :achievement, null: false, foreign_key: true
  end
end
