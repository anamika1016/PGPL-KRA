class AddEmployeeDetailToUserTrainingAssignments < ActiveRecord::Migration[8.0]
  def change
    # Remove old unique index on [user_id, training_id]
    remove_index :user_training_assignments, [ :user_id, :training_id ], if_exists: true

    # Make user_id nullable (some employees may not have a User login yet)
    change_column_null :user_training_assignments, :user_id, true

    # Add employee_detail_id (nullable for existing rows without it)
    add_reference :user_training_assignments, :employee_detail, null: true, foreign_key: true

    # New unique constraint: one assignment per employee_detail + training
    add_index :user_training_assignments, [ :employee_detail_id, :training_id ],
              unique: true,
              name: "index_uta_on_employee_detail_and_training"
  end
end
