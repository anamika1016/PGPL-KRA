require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "auto provisions a user from employee details on first login" do
    employee = EmployeeDetail.create!(
      employee_id: "AUTO001",
      employee_name: "Auto Login User",
      employee_email: "auto.login@example.com",
      employee_code: "AUTO001",
      department: "Project",
      post: "Executive"
    )

    assert_difference("User.count", 1) do
      post user_session_path, params: {
        user: {
          email: "",
          employee_code: employee.employee_code,
          password: User::DEFAULT_EMPLOYEE_PASSWORD
        }
      }
    end

    user = User.find_by(employee_code: employee.employee_code)

    assert_redirected_to dashboard_path
    assert_not_nil user
    assert_equal "employee", user.role
    assert_equal employee.employee_email, user.email
    assert_equal user.id, employee.reload.user_id
  end

  test "existing user can sign in with employee code without email" do
    user = User.create!(
      email: "code.only@example.com",
      employee_code: "CODE123",
      role: "employee",
      password: "secret123",
      password_confirmation: "secret123"
    )

    assert_no_difference("User.count") do
      post user_session_path, params: {
        user: {
          email: "",
          employee_code: user.employee_code,
          password: "secret123"
        }
      }
    end

    assert_redirected_to dashboard_path
  end
end
