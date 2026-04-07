class AddScoreToUserTrainingProgresses < ActiveRecord::Migration[8.0]
  def change
    add_column :user_training_progresses, :score, :integer
  end
end
