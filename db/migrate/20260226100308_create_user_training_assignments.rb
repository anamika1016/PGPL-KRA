class CreateUserTrainingAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :user_training_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :training, null: false, foreign_key: true

      t.timestamps
    end
    add_index :user_training_assignments, [ :user_id, :training_id ], unique: true
  end
end
