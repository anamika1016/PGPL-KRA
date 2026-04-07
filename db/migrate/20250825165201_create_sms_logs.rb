class CreateSmsLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_logs do |t|
      t.string :quarter
      t.boolean :sent
      t.datetime :sent_at
      t.references :employee_detail, null: false, foreign_key: true

      t.timestamps
    end
  end
end
