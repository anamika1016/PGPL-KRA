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

  test "l1 menu logic works when user employee code is stale but linked employee detail code is correct" do
    l1_user = User.create!(
      email: "dheer.agnihotri@example.com",
      password: "password123",
      password_confirmation: "password123",
      role: "employee",
      employee_code: "OLD-CODE"
    )

    l1_self_detail = EmployeeDetail.create!(
      employee_id: "EMP-008",
      employee_name: "Dheer Agnihotri",
      employee_email: l1_user.email,
      employee_code: "PGPL-008",
      l1_code: "PGPL-002",
      l1_employer_name: "manager@example.com",
      l2_code: "PGPL-001",
      l2_employer_name: "l2@example.com",
      post: "Executive",
      department: "Project",
      status: "pending",
      user: l1_user
    )

    managed_employee = EmployeeDetail.create!(
      employee_id: "EMP-004",
      employee_name: "Deepak Singh",
      employee_email: "deepak.singh@example.com",
      employee_code: "PGPL-004",
      l1_code: "PGPL-008",
      l1_employer_name: l1_user.email,
      l2_code: "PGPL-002",
      l2_employer_name: "l2@example.com",
      post: "Executive",
      department: "Project",
      status: "pending"
    )

    department = Department.create!(
      department_type: "Project",
      financial_year: "2026-27"
    )

    activity = Activity.create!(
      activity_name: "Project Delivery",
      department: department,
      financial_year: "2026-27",
      unit: "Nos",
      weight: 1.0
    )

    user_detail = UserDetail.create!(
      department: department,
      activity: activity,
      employee_detail: managed_employee,
      financial_year: "2026-27"
    )

    Achievement.create!(
      user_detail: user_detail,
      month: "april",
      achievement: "10",
      status: "pending"
    )

    sign_in l1_user

    get l1_employee_details_path(financial_year: "2026-27")

    assert_response :success
    assert_match "Deepak Singh", @response.body
  end
end
