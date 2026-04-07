class CreateUserTrainingProgresses < ActiveRecord::Migration[8.0]
  def change
    create_table :user_training_progresses do |t|
      t.references :training, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status
      t.datetime :started_at
      t.datetime :ended_at
      t.integer :time_spent
      t.string :financial_year

      t.timestamps
    end
  end
end
