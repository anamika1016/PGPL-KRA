class AddApprovalFieldsToAchievements < ActiveRecord::Migration[8.0]
  def change
    add_column :achievements, :status, :string, default: "pending"
    add_column :achievements, :l1_remarks, :text
    add_column :achievements, :l1_percentage, :float
    add_column :achievements, :l2_remarks, :text
    add_column :achievements, :l2_percentage, :float
  end
end
