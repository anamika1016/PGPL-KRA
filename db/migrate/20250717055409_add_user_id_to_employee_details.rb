class AddUserIdToEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    add_reference :employee_details, :user, foreign_key: true  # remove `null: false`
  end
end
