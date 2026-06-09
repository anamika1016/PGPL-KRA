class CreateEmployeeTrainings < ActiveRecord::Migration[8.0]
  def change
    create_table :employee_trainings do |t|
      t.references :user, null: false, foreign_key: true
      t.jsonb :office_types, null: false, default: []
      t.jsonb :office_names, null: false, default: []
      t.string :thematic_department_name, null: false
      t.date :training_date, null: false
      t.string :topic, null: false
      t.string :other_topic
      t.text :details, null: false
      t.string :training_location, null: false
      t.integer :asa_participants, null: false, default: 0
      t.integer :other_participants, null: false, default: 0
      t.string :qr_id, null: false
      t.jsonb :employee_detail_ids, null: false, default: []

      t.timestamps
    end

    add_index :employee_trainings, :training_date
    add_index :employee_trainings, :thematic_department_name
    add_index :employee_trainings, :created_at
  end
end
