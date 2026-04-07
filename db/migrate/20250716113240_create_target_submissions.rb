class CreateTargetSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :target_submissions do |t|
      t.references :user_detail, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :employee_detail, null: false, foreign_key: true
      t.string :month
      t.string :target
      t.string :status

      t.timestamps
    end
  end
end
