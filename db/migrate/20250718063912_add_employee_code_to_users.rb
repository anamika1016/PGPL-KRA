class AddEmployeeCodeToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :employee_code, :string
  end
end
