class UpdateDurationToSeconds < ActiveRecord::Migration[8.0]
  def up
    Training.all.each do |training|
      # Multiply existing duration (minutes) by 60 to convert to seconds
      training.update_column(:duration, (training.duration.to_i * 60))
    end
  end

  def down
    Training.all.each do |training|
      # Divide by 60 to return to minutes
      training.update_column(:duration, (training.duration.to_i / 60))
    end
  end
end
