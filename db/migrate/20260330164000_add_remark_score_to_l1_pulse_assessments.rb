class AddRemarkScoreToL1PulseAssessments < ActiveRecord::Migration[8.0]
  def change
    add_column :l1_pulse_assessments, :remark_score, :integer
  end
end
