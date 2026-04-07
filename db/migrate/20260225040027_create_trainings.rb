class CreateTrainings < ActiveRecord::Migration[8.0]
  def change
    create_table :trainings do |t|
      t.string :title
      t.text :description
      t.integer :duration
      t.integer :created_by
      t.integer :month
      t.integer :year
      t.boolean :status

      t.timestamps
    end
  end
end
