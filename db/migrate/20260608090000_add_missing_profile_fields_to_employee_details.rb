class AddMissingProfileFieldsToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :office_type, :string unless column_exists?(:employee_details, :office_type)
    add_column :employee_details, :office_name, :string unless column_exists?(:employee_details, :office_name)
    add_column :employee_details, :designation, :string unless column_exists?(:employee_details, :designation)
    add_column :employee_details, :position, :string unless column_exists?(:employee_details, :position)
    add_column :employee_details, :vertical, :string unless column_exists?(:employee_details, :vertical)
  end
end
