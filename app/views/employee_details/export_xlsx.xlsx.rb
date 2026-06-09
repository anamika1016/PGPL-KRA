package = Axlsx::Package.new
workbook = package.workbook

workbook.add_worksheet(name: "Employees") do |sheet|
  sheet.add_row [
    "Name", "Email", "Mobile Number", "Employee Code",
    "Office Type", "Office Name",
    "L1 Code", "L1 Name", "L2 Code", "L2 Name",
    "Post", "Designation", "Position", "Department", "Vertical"
  ]
  @employee_details.each do |emp|
    sheet.add_row [
      emp.employee_name,
      emp.employee_email,
      emp.mobile_number,
      emp.employee_code,
      emp.office_type,
      emp.office_name,
      emp.l1_code,
      emp.l1_employer_name,
      emp.l2_code,
      emp.l2_employer_name,
      emp.post,
      emp.designation,
      emp.position,
      emp.department,
      emp.vertical
    ]
  end
end

# Set response headers and render file
tempfile = Tempfile.new([ "employee_details", ".xlsx" ])
package.serialize(tempfile.path)

send_file tempfile.path, filename: "employee_details.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
