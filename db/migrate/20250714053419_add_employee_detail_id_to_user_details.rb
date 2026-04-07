class AddEmployeeDetailIdToUserDetails < ActiveRecord::Migration[8.0]
  def change
   add_reference :user_details, :employee_detail, null: true, foreign_key: true
  end
end
