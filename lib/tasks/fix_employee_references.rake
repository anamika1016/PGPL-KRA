namespace :departments do
  desc "Check and fix employee references in departments"
  task fix_employee_references: :environment do
    puts "Checking department employee references..."

    Department.all.each do |dept|
      puts "\nDepartment ID: #{dept.id}"
      puts "Department Type: #{dept.department_type}"
      puts "Employee Reference: '#{dept.employee_reference}'"

      if dept.employee_reference.blank?
        puts "  ❌ Employee reference is blank!"
      else
        employee = EmployeeDetail.find_by(employee_id: dept.employee_reference)
        if employee
          puts "  ✅ Found employee: #{employee.employee_name}"
        else
          puts "  ❌ Employee with ID '#{dept.employee_reference}' not found!"
          # List available employees
          puts "  Available employees:"
          EmployeeDetail.limit(5).each do |emp|
            puts "    - #{emp.employee_name} (#{emp.employee_id})"
          end
        end
      end
    end

    puts "\n" + "="*50
    puts "Employee Details Summary:"
    puts "Total employees: #{EmployeeDetail.count}"
    puts "Employees with employee_id: #{EmployeeDetail.where.not(employee_id: nil).count}"
    puts "Employees with employee_name: #{EmployeeDetail.where.not(employee_name: nil).count}"

    puts "\nFirst 5 employees:"
    EmployeeDetail.limit(5).each do |emp|
      puts "  #{emp.employee_name} (ID: #{emp.employee_id})"
    end
  end
end
