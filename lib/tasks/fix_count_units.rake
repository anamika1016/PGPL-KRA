namespace :fix do
  desc "Fix all activities with 'Count' unit values - replace with blank or '%'"
  task count_units: :environment do
    puts "=== Fixing Count Unit Values ==="

    # Find all activities with "Count" as unit
    activities_with_count = Activity.where(unit: "Count")
    total_count = activities_with_count.count

    if total_count == 0
      puts "✅ No activities found with 'Count' unit values. Nothing to fix."
      return
    end

    puts "Found #{total_count} activities with 'Count' unit values."
    puts "Options:"
    puts "1. Replace all 'Count' with blank (empty string)"
    puts "2. Replace all 'Count' with '%'"
    puts "3. Show details first, then choose"

    print "Enter your choice (1, 2, or 3): "
    choice = STDIN.gets.chomp

    case choice
    when "1"
      puts "Replacing all 'Count' values with blank..."
      updated_count = activities_with_count.update_all(unit: "")
      puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with blank."

    when "2"
      puts "Replacing all 'Count' values with '%'..."
      updated_count = activities_with_count.update_all(unit: "%")
      puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with '%'."

    when "3"
      puts "\n=== Details of Activities with 'Count' Unit ==="
      activities_with_count.includes(:department).limit(10).each do |activity|
        puts "ID: #{activity.id}, Name: #{activity.activity_name}, Department: #{activity.department&.department_type}, Theme: #{activity.theme_name}"
      end

      if total_count > 10
        puts "... and #{total_count - 10} more activities"
      end

      puts "\nOptions:"
      puts "1. Replace all 'Count' with blank (empty string)"
      puts "2. Replace all 'Count' with '%'"

      print "Enter your choice (1 or 2): "
      choice2 = STDIN.gets.chomp

      case choice2
      when "1"
        puts "Replacing all 'Count' values with blank..."
        updated_count = activities_with_count.update_all(unit: "")
        puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with blank."

      when "2"
        puts "Replacing all 'Count' values with '%'..."
        updated_count = activities_with_count.update_all(unit: "%")
        puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with '%'."

      else
        puts "❌ Invalid choice. No changes made."
      end

    else
      puts "❌ Invalid choice. No changes made."
    end

    puts "\n=== Summary ==="
    remaining_count = Activity.where(unit: "Count").count
    puts "Activities still with 'Count' unit: #{remaining_count}"

    if remaining_count == 0
      puts "🎉 All 'Count' unit values have been successfully fixed!"
    else
      puts "⚠️  Some activities still have 'Count' unit values."
    end
  end

  desc "Automatically replace all 'Count' unit values with '%' (non-interactive)"
  task count_units_to_percent: :environment do
    puts "=== Automatically Replacing Count Units with % ==="

    # Find all activities with "Count" as unit
    activities_with_count = Activity.where(unit: "Count")
    total_count = activities_with_count.count

    if total_count == 0
      puts "✅ No activities found with 'Count' unit values. Nothing to fix."
      return
    end

    puts "Found #{total_count} activities with 'Count' unit values."
    puts "Automatically replacing all 'Count' values with '%'..."

    # Update all activities with "Count" unit to "%"
    updated_count = activities_with_count.update_all(unit: "%")

    puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with '%'."

    # Verify the change
    remaining_count = Activity.where(unit: "Count").count
    if remaining_count == 0
      puts "🎉 All 'Count' unit values have been successfully replaced with '%'!"
    else
      puts "⚠️  Some activities still have 'Count' unit values: #{remaining_count}"
    end
  end

  desc "Automatically replace all 'Count' unit values with blank (non-interactive)"
  task count_units_to_blank: :environment do
    puts "=== Automatically Replacing Count Units with Blank ==="

    # Find all activities with "Count" as unit
    activities_with_count = Activity.where(unit: "Count")
    total_count = activities_with_count.count

    if total_count == 0
      puts "✅ No activities found with 'Count' unit values. Nothing to fix."
      return
    end

    puts "Found #{total_count} activities with 'Count' unit values."
    puts "Automatically replacing all 'Count' values with blank..."

    # Update all activities with "Count" unit to blank
    updated_count = activities_with_count.update_all(unit: "")

    puts "✅ Successfully updated #{updated_count} activities. All 'Count' values replaced with blank."

    # Verify the change
    remaining_count = Activity.where(unit: "Count").count
    if remaining_count == 0
      puts "🎉 All 'Count' unit values have been successfully replaced with blank!"
    else
      puts "⚠️  Some activities still have 'Count' unit values: #{remaining_count}"
    end
  end

  desc "Show count of activities with 'Count' unit values"
  task count_units_status: :environment do
    puts "=== Count Unit Status ==="

    total_activities = Activity.count
    count_activities = Activity.where(unit: "Count").count
    blank_activities = Activity.where(unit: "").count
    percent_activities = Activity.where(unit: "%").count
    other_units = total_activities - count_activities - blank_activities - percent_activities

    puts "Total activities: #{total_activities}"
    puts "Activities with 'Count' unit: #{count_activities}"
    puts "Activities with blank unit: #{blank_activities}"
    puts "Activities with '%' unit: #{percent_activities}"
    puts "Activities with other units: #{other_units}"

    if count_activities > 0
      puts "\n⚠️  There are still #{count_activities} activities with 'Count' unit values."
      puts "Run 'rake fix:count_units_to_percent' to replace all with '%'"
      puts "Run 'rake fix:count_units_to_blank' to replace all with blank"
      puts "Run 'rake fix:count_units' for interactive choice"
    else
      puts "\n✅ All activities have been fixed. No 'Count' unit values found."
    end
  end
end
