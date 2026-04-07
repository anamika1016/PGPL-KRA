class AddAssignmentsManagedToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :assignments_managed, :boolean, default: false
  end
end
