class CreateL1PulseAssessments < ActiveRecord::Migration[8.0]
  def change
    create_table :l1_pulse_assessments do |t|
      t.references :employee_detail, null: false, foreign_key: true
      t.references :l1_user, null: false, foreign_key: { to_table: :users }
      t.integer :values_alignment
      t.integer :technical_knowledge
      t.integer :customer_field_engagement
      t.integer :execution_accountability
      t.integer :initiative_leadership
      t.text :remarks

      t.timestamps
    end

    add_index :l1_pulse_assessments, [ :employee_detail_id, :l1_user_id ], unique: true, name: "index_l1_pulse_assessments_on_employee_and_l1_user"
  end
end
