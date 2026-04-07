class AddEmployeeRemarksToAchievements < ActiveRecord::Migration[8.0]
  def change
    add_column :achievements, :employee_remarks, :text
  end
end
