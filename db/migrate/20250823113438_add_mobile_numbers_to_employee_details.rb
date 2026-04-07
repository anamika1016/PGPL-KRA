class AddMobileNumbersToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_column :employee_details, :mobile_number, :string
  end
end
