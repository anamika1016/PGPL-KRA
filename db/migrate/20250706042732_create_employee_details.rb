class CreateEmployeeDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :employee_details do |t|
      t.string :employee_id
      t.string :employee_name
      t.string :employee_email
      t.string :employee_code
      t.string :l1_code
      t.string :l2_code
      t.string :l1_employer_name
      t.string :l2_employer_name
      t.string :post
      t.string :department

      t.timestamps
    end
  end
end
