class CreateEmployeeTrainingTopics < ActiveRecord::Migration[8.0]
  def change
    create_table :employee_training_topics do |t|
      t.string :thematic_department_name, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :employee_training_topics,
      [ :thematic_department_name, :name ],
      unique: true,
      name: "index_employee_training_topics_on_thematic_and_name"
  end
end
