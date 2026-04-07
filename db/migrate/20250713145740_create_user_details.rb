class CreateUserDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :user_details do |t|
      t.references :department, null: false, foreign_key: true
      t.references :activity, null: false, foreign_key: true
      t.text :april
      t.text :may
      t.text :june
      t.text :july
      t.text :august
      t.text :september
      t.text :october
      t.text :november
      t.text :december
      t.text :january
      t.text :february
      t.text :march

      t.timestamps
    end
  end
end
