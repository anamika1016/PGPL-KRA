class RemoveL3Fields < ActiveRecord::Migration[8.0]
  def change
    remove_column :employee_details, :l3_code, :string if column_exists?(:employee_details, :l3_code)
    remove_column :employee_details, :l3_employer_name, :string if column_exists?(:employee_details, :l3_employer_name)

    if column_exists?(:helpdesk_escalation_matrices, :l3_user_id)
      remove_foreign_key :helpdesk_escalation_matrices, column: :l3_user_id if foreign_key_exists?(:helpdesk_escalation_matrices, column: :l3_user_id)
      remove_index :helpdesk_escalation_matrices, column: :l3_user_id if index_exists?(:helpdesk_escalation_matrices, :l3_user_id)
      remove_column :helpdesk_escalation_matrices, :l3_user_id, :bigint
    end
  end
end
