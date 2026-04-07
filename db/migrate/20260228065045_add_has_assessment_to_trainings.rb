class AddHasAssessmentToTrainings < ActiveRecord::Migration[8.0]
  def change
    add_column :trainings, :has_assessment, :boolean
  end
end
