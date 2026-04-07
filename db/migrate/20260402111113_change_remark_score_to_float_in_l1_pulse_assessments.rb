class ChangeRemarkScoreToFloatInL1PulseAssessments < ActiveRecord::Migration[8.0]
  def change
    change_column :l1_pulse_assessments, :remark_score, :float
  end
end
