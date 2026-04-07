class AddL1AndL2RemarksAndPercentageToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :l1_remarks, :text
    add_column :employee_details, :l1_percentage, :float
    add_column :employee_details, :l2_remarks, :text
    add_column :employee_details, :l2_percentage, :float
  end
end
