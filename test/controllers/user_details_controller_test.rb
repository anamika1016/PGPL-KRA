require "test_helper"
require "axlsx"
require "rack/test"

class UserDetailsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "import reports a misspelled required header" do
    upload, tempfile = build_excel_upload([
      [ "Financial Year", "Department", "Employee Nmae", "Activity Name", "April" ],
      [ "2025-26", "Sales", "Amit Kumar", "Outlet Visits", 10 ]
    ])

    post import_user_details_url, params: { file: upload, financial_year: "2025-26" }

    assert_redirected_to new_user_detail_path(financial_year: "2025-26")
    follow_redirect!

    assert_match "Missing required column(s): Employee Name.", flash[:alert]
    assert_match "'Employee Nmae' ko 'Employee Name' likhiye", flash[:alert]
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  test "import reports blank data rows clearly" do
    upload, tempfile = build_excel_upload([
      [ nil, nil, nil, nil, nil ],
      [ "Financial Year", "Department", "Employee Name", "Activity Name", "April" ],
      [ "", "", "", "", "" ]
    ])

    post import_user_details_url, params: { file: upload, financial_year: "2025-26" }

    assert_redirected_to new_user_detail_path(financial_year: "2025-26")
    follow_redirect!

    assert_match "Sabhi 1 data row blank mile.", flash[:alert]
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  test "import uses department and activity records for the row financial year" do
    old_department = Department.create!(department_type: "QA Import Dept", financial_year: "2024-25")
    Activity.create!(
      activity_name: "Yearly Audit",
      department: old_department,
      financial_year: "2024-25",
      unit: "Nos",
      weight: 1.0
    )

    upload, tempfile = build_excel_upload([
      [ "Financial Year", "Department", "Employee Name", "Employee Email", "Employee Code", "Activity Name", "Theme Name", "Unit", "April" ],
      [ "2025-26", "QA Import Dept", "Import User", "import.user@example.com", "IMP001", "Yearly Audit", "Compliance", "Nos", 10 ]
    ])

    post import_user_details_url, params: { file: upload, financial_year: "2025-26" }

    assert_redirected_to new_user_detail_path(financial_year: "2025-26")
    follow_redirect!

    assert_match "Excel file imported successfully!", flash[:notice]

    new_department = Department.find_by!(department_type: "QA Import Dept", financial_year: "2025-26")
    new_activity = Activity.find_by!(activity_name: "Yearly Audit", department_id: new_department.id, financial_year: "2025-26")
    employee = EmployeeDetail.find_by!(employee_code: "IMP001")

    assert UserDetail.exists?(
      employee_detail_id: employee.id,
      department_id: new_department.id,
      activity_id: new_activity.id,
      financial_year: "2025-26"
    )
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  private

  def build_excel_upload(rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Department Activity Data") do |sheet|
      rows.each { |row| sheet.add_row(row) }
    end

    tempfile = Tempfile.new([ "user-detail-import", ".xlsx" ])
    package.serialize(tempfile.path)

    upload = Rack::Test::UploadedFile.new(
      tempfile.path,
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )

    [ upload, tempfile ]
  end
end
