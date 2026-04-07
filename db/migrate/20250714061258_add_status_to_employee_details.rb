class AddStatusToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :status, :string, default: "pending"
  end
end
