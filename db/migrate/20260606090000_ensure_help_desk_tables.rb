class EnsureHelpDeskTables < ActiveRecord::Migration[8.0]
  def up
    create_helpdesk_escalation_matrices
    create_helpdesk_escalation_levels
    create_help_desk_question_masters
    create_help_desk_tickets
    create_help_desk_support_updates
    create_help_desk_requester_remarks
  end

  def down
    drop_table :help_desk_requester_remarks, if_exists: true
    drop_table :help_desk_support_updates, if_exists: true
    drop_table :help_desk_tickets, if_exists: true
    drop_table :help_desk_question_masters, if_exists: true
    drop_table :helpdesk_escalation_levels, if_exists: true
    drop_table :helpdesk_escalation_matrices, if_exists: true
  end

  private

  def create_helpdesk_escalation_matrices
    create_table :helpdesk_escalation_matrices, if_not_exists: true do |t|
      t.references :department, null: false, foreign_key: true
      t.references :l1_user, foreign_key: { to_table: :users }
      t.references :l2_user, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_reference_if_missing :helpdesk_escalation_matrices, :department, null: false, foreign_key: true
    add_reference_if_missing :helpdesk_escalation_matrices, :l1_user, foreign_key: { to_table: :users }
    add_reference_if_missing :helpdesk_escalation_matrices, :l2_user, foreign_key: { to_table: :users }
    add_timestamps_if_missing :helpdesk_escalation_matrices
    add_index_if_missing :helpdesk_escalation_matrices, :department_id, unique: true
  end

  def create_helpdesk_escalation_levels
    create_table :helpdesk_escalation_levels, if_not_exists: true do |t|
      t.references :helpdesk_escalation_matrix, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end

    add_reference_if_missing :helpdesk_escalation_levels, :helpdesk_escalation_matrix, null: false, foreign_key: true
    add_reference_if_missing :helpdesk_escalation_levels, :user, null: false, foreign_key: true
    add_column_if_missing :helpdesk_escalation_levels, :position, :integer, null: false
    add_timestamps_if_missing :helpdesk_escalation_levels
    add_index_if_missing :helpdesk_escalation_levels, [ :helpdesk_escalation_matrix_id, :position ], unique: true, name: "idx_helpdesk_levels_on_matrix_and_position"
  end

  def create_help_desk_question_masters
    create_table :help_desk_question_masters, if_not_exists: true do |t|
      t.references :department, null: false, foreign_key: true
      t.string :request_type, null: false
      t.text :question_text, null: false
      t.integer :position, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_reference_if_missing :help_desk_question_masters, :department, null: false, foreign_key: true
    add_column_if_missing :help_desk_question_masters, :request_type, :string, null: false
    add_column_if_missing :help_desk_question_masters, :question_text, :text, null: false
    add_column_if_missing :help_desk_question_masters, :position, :integer, null: false, default: 1
    add_column_if_missing :help_desk_question_masters, :active, :boolean, null: false, default: true
    add_timestamps_if_missing :help_desk_question_masters
    add_index_if_missing :help_desk_question_masters, [ :department_id, :request_type, :position ], name: "idx_helpdesk_questions_on_department_type_position"
    add_index_if_missing :help_desk_question_masters, [ :department_id, :request_type, :question_text ], unique: true, name: "idx_helpdesk_questions_unique_text"
  end

  def create_help_desk_tickets
    create_table :help_desk_tickets, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :department, null: false, foreign_key: true
      t.string :request_type, null: false
      t.string :status, null: false, default: "submitted"
      t.string :requester_name, null: false
      t.string :requester_email, null: false
      t.string :requester_employee_code
      t.text :message, null: false
      t.references :assigned_to_user, foreign_key: { to_table: :users }
      t.references :responded_by_user, foreign_key: { to_table: :users }
      t.integer :current_escalation_position
      t.datetime :assigned_at
      t.datetime :escalation_due_at
      t.text :response_message
      t.datetime :responded_at
      t.references :submitted_by_user, foreign_key: { to_table: :users }
      t.boolean :raised_on_behalf, null: false, default: false
      t.datetime :requester_response_due_at
      t.text :requester_remark
      t.datetime :closed_at
      t.boolean :closed_automatically, null: false, default: false
      t.references :closed_by_user, foreign_key: { to_table: :users }
      t.references :help_desk_question_master, foreign_key: true
      t.text :question_subject
      t.references :approval_user, foreign_key: { to_table: :users }
      t.string :final_action_mode
      t.integer :reopen_count, null: false, default: 0
      t.datetime :request_received_at
      t.jsonb :failed_response_counts, null: false, default: {}
      t.timestamps
    end

    add_reference_if_missing :help_desk_tickets, :user, null: false, foreign_key: true
    add_reference_if_missing :help_desk_tickets, :department, null: false, foreign_key: true
    add_column_if_missing :help_desk_tickets, :request_type, :string, null: false
    add_column_if_missing :help_desk_tickets, :status, :string, null: false, default: "submitted"
    add_column_if_missing :help_desk_tickets, :requester_name, :string, null: false
    add_column_if_missing :help_desk_tickets, :requester_email, :string, null: false
    add_column_if_missing :help_desk_tickets, :requester_employee_code, :string
    add_column_if_missing :help_desk_tickets, :message, :text, null: false
    add_reference_if_missing :help_desk_tickets, :assigned_to_user, foreign_key: { to_table: :users }
    add_reference_if_missing :help_desk_tickets, :responded_by_user, foreign_key: { to_table: :users }
    add_column_if_missing :help_desk_tickets, :current_escalation_position, :integer
    add_column_if_missing :help_desk_tickets, :assigned_at, :datetime
    add_column_if_missing :help_desk_tickets, :escalation_due_at, :datetime
    add_column_if_missing :help_desk_tickets, :response_message, :text
    add_column_if_missing :help_desk_tickets, :responded_at, :datetime
    add_reference_if_missing :help_desk_tickets, :submitted_by_user, foreign_key: { to_table: :users }
    add_column_if_missing :help_desk_tickets, :raised_on_behalf, :boolean, null: false, default: false
    add_column_if_missing :help_desk_tickets, :requester_response_due_at, :datetime
    add_column_if_missing :help_desk_tickets, :requester_remark, :text
    add_column_if_missing :help_desk_tickets, :closed_at, :datetime
    add_column_if_missing :help_desk_tickets, :closed_automatically, :boolean, null: false, default: false
    add_reference_if_missing :help_desk_tickets, :closed_by_user, foreign_key: { to_table: :users }
    add_reference_if_missing :help_desk_tickets, :help_desk_question_master, foreign_key: true
    add_column_if_missing :help_desk_tickets, :question_subject, :text
    add_reference_if_missing :help_desk_tickets, :approval_user, foreign_key: { to_table: :users }
    add_column_if_missing :help_desk_tickets, :final_action_mode, :string
    add_column_if_missing :help_desk_tickets, :reopen_count, :integer, null: false, default: 0
    add_column_if_missing :help_desk_tickets, :request_received_at, :datetime
    add_column_if_missing :help_desk_tickets, :failed_response_counts, :jsonb, null: false, default: {}
    add_timestamps_if_missing :help_desk_tickets

    add_index_if_missing :help_desk_tickets, :status
    add_index_if_missing :help_desk_tickets, :request_type
    add_index_if_missing :help_desk_tickets, :escalation_due_at
    add_index_if_missing :help_desk_tickets, :requester_response_due_at
    add_index_if_missing :help_desk_tickets, :request_received_at
    add_index_if_missing :help_desk_tickets, :final_action_mode
  end

  def create_help_desk_support_updates
    create_table :help_desk_support_updates, if_not_exists: true do |t|
      t.references :help_desk_ticket, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :message, null: false
      t.timestamps
    end

    add_reference_if_missing :help_desk_support_updates, :help_desk_ticket, null: false, foreign_key: true
    add_reference_if_missing :help_desk_support_updates, :user, foreign_key: true
    add_column_if_missing :help_desk_support_updates, :message, :text, null: false
    add_timestamps_if_missing :help_desk_support_updates
  end

  def create_help_desk_requester_remarks
    create_table :help_desk_requester_remarks, if_not_exists: true do |t|
      t.references :help_desk_ticket, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :message, null: false
      t.timestamps
    end

    add_reference_if_missing :help_desk_requester_remarks, :help_desk_ticket, null: false, foreign_key: true
    add_reference_if_missing :help_desk_requester_remarks, :user, foreign_key: true
    add_column_if_missing :help_desk_requester_remarks, :message, :text, null: false
    add_timestamps_if_missing :help_desk_requester_remarks
  end

  def add_column_if_missing(table_name, column_name, type, **options)
    return if column_exists?(table_name, column_name)

    add_column table_name, column_name, type, **options
  end

  def add_reference_if_missing(table_name, reference_name, **options)
    return if column_exists?(table_name, "#{reference_name}_id")

    add_reference table_name, reference_name, **options
  end

  def add_index_if_missing(table_name, columns, **options)
    return if index_exists?(table_name, columns, **options.slice(:name))
    return if options[:name].blank? && index_exists?(table_name, columns)

    add_index table_name, columns, **options
  end

  def add_timestamps_if_missing(table_name)
    add_column_if_missing table_name, :created_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
    add_column_if_missing table_name, :updated_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
  end
end
