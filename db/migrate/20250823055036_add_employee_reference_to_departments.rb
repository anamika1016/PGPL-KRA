class AddEmployeeReferenceToDepartments < ActiveRecord::Migration[8.0]
  def change
    add_column :departments, :employee_reference, :string
  end
end
