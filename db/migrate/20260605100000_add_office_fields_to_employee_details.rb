class AddOfficeFieldsToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :office_type, :string unless column_exists?(:employee_details, :office_type)
    add_column :employee_details, :office_name, :string unless column_exists?(:employee_details, :office_name)
  end
end
