class AddCriteriaToL1PulseAssessment < ActiveRecord::Migration[8.0]
  def change
    add_column :l1_pulse_assessments, :professionalism_conduct, :integer
    add_column :l1_pulse_assessments, :work_quality_accuracy, :integer
    add_column :l1_pulse_assessments, :initiative_problem_solving, :integer
    add_column :l1_pulse_assessments, :papl_values_culture, :integer
    add_column :l1_pulse_assessments, :collaboration, :integer
    add_column :l1_pulse_assessments, :time_management_reliability, :integer
    add_column :l1_pulse_assessments, :growth_mindset_development, :integer
  end
end
