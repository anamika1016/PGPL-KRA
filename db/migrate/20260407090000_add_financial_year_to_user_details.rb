class AddFinancialYearToUserDetails < ActiveRecord::Migration[8.0]
  class MigrationUserDetail < ApplicationRecord
    self.table_name = "user_details"
  end

  class MigrationActivity < ApplicationRecord
    self.table_name = "activities"
  end

  def up
    add_column :user_details, :financial_year, :string unless column_exists?(:user_details, :financial_year)
    add_column :user_details, :theme_name, :string unless column_exists?(:user_details, :theme_name)
    add_column :user_details, :unit, :string unless column_exists?(:user_details, :unit)

    add_index :user_details, :financial_year unless index_exists?(:user_details, :financial_year)
    add_index :user_details, [ :employee_detail_id, :financial_year ] unless index_exists?(:user_details, [ :employee_detail_id, :financial_year ])
    unless index_exists?(:user_details, [ :department_id, :activity_id, :employee_detail_id, :financial_year ],
                         name: "index_user_details_on_department_activity_employee_fy")
      add_index :user_details,
                [ :department_id, :activity_id, :employee_detail_id, :financial_year ],
                name: "index_user_details_on_department_activity_employee_fy"
    end

    financial_year_available = column_exists?(:user_details, :financial_year)
    theme_name_available = column_exists?(:user_details, :theme_name)
    unit_available = column_exists?(:user_details, :unit)

    MigrationUserDetail.reset_column_information

    say_with_time "Backfilling financial years for user details" do
      MigrationUserDetail.find_each do |detail|
        updates = {}

        if financial_year_available && detail.financial_year.blank?
          updates[:financial_year] = financial_year_for(detail.created_at || Time.current)
        end

        if (theme_name_available && detail.theme_name.blank? || unit_available && detail.unit.blank?) && detail.activity_id.present?
          activity = MigrationActivity.find_by(id: detail.activity_id)
          updates[:theme_name] = activity&.theme_name if theme_name_available && detail.theme_name.blank?
          updates[:unit] = activity&.unit if unit_available && detail.unit.blank?
        end

        detail.update_columns(updates) if updates.any?
      end
    end

    change_column_null :user_details, :financial_year, false if financial_year_available
  end

  def down
    if index_exists?(:user_details, [ :department_id, :activity_id, :employee_detail_id, :financial_year ],
                     name: "index_user_details_on_department_activity_employee_fy")
      remove_index :user_details, name: "index_user_details_on_department_activity_employee_fy"
    end
    remove_index :user_details, [ :employee_detail_id, :financial_year ] if index_exists?(:user_details, [ :employee_detail_id, :financial_year ])
    remove_index :user_details, :financial_year if index_exists?(:user_details, :financial_year)
    remove_column :user_details, :unit if column_exists?(:user_details, :unit)
    remove_column :user_details, :theme_name if column_exists?(:user_details, :theme_name)
    remove_column :user_details, :financial_year if column_exists?(:user_details, :financial_year)
  end

  private

  def financial_year_for(timestamp)
    date = timestamp.to_date
    start_year = date.month >= 4 ? date.year : date.year - 1
    "#{start_year}-#{(start_year + 1).to_s.last(2)}"
  end
end
