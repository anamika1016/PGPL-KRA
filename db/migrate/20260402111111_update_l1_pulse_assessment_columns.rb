class UpdateL1PulseAssessmentColumns < ActiveRecord::Migration[8.0]
  def change
    remove_column :l1_pulse_assessments, :values_alignment, :integer
    remove_column :l1_pulse_assessments, :technical_knowledge, :integer
    remove_column :l1_pulse_assessments, :customer_field_engagement, :integer
    remove_column :l1_pulse_assessments, :execution_accountability, :integer
    remove_column :l1_pulse_assessments, :initiative_leadership, :integer

    add_column :l1_pulse_assessments, :sense_of_purpose, :integer
    add_column :l1_pulse_assessments, :workload_balance, :integer
    add_column :l1_pulse_assessments, :manager_effectiveness, :integer
    add_column :l1_pulse_assessments, :team_collaboration, :integer
    add_column :l1_pulse_assessments, :recognition_growth, :integer
    add_column :l1_pulse_assessments, :org_communication, :integer
    add_column :l1_pulse_assessments, :learning_development, :integer
    add_column :l1_pulse_assessments, :role_clarity, :integer
    add_column :l1_pulse_assessments, :work_environment, :integer
    add_column :l1_pulse_assessments, :commitment_retention, :integer
  end
end
