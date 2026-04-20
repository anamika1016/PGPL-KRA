require "test_helper"

class EmployeeDetailsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "l1 view shows employees assigned through l1 employer email" do
    l1_user = User.create!(
      email: "l1.manager@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: "l1_employer",
      employee_code: "L1EMAIL001"
    )

    employee_detail = EmployeeDetail.create!(
      employee_id: "EMP-100",
      employee_name: "Visible Employee",
      employee_email: "visible.employee@example.com",
      employee_code: "EMP100",
      l1_code: "SOMEONEELSE",
      l1_employer_name: l1_user.email,
      l2_code: "L2001",
      l2_employer_name: "l2.manager@example.com",
      post: "Executive",
      department: "Sales",
      status: "pending"
    )

    department = Department.create!(
      department_type: "Sales",
      financial_year: "2026-27"
    )

    activity = Activity.create!(
      activity_name: "Outlet Coverage",
      department: department,
      financial_year: "2026-27",
      unit: "Nos",
      weight: 1.0
    )

    user_detail = UserDetail.create!(
      department: department,
      activity: activity,
      employee_detail: employee_detail,
      financial_year: "2026-27"
    )

    Achievement.create!(
      user_detail: user_detail,
      month: "april",
      achievement: "12",
      status: "pending"
    )

    sign_in l1_user

    get l1_employee_details_path(financial_year: "2026-27")

    assert_response :success
    assert_match "Visible Employee", @response.body
  end
end
