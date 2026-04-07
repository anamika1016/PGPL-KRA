class CreateDepartments < ActiveRecord::Migration[8.0]
  def change
    create_table :departments do |t|
      t.string :department_type
      t.integer :theme_id
      t.string :theme_name

      t.timestamps
    end
  end
end
