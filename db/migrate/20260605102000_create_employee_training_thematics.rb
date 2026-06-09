class CreateEmployeeTrainingThematics < ActiveRecord::Migration[8.0]
  def change
    create_table :employee_training_thematics do |t|
      t.string :thematic_type, null: false
      t.string :department_name, null: false
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :employee_training_thematics,
      [ :thematic_type, :department_name ],
      unique: true,
      name: "index_employee_training_thematics_on_type_and_department"
  end
end
