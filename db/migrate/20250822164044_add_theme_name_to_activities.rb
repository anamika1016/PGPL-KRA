class AddThemeNameToActivities < ActiveRecord::Migration[8.0]
  def change
    add_column :activities, :theme_name, :string
  end
end
