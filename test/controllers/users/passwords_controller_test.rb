require "test_helper"

class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "forgot password with unknown email re-renders page without crashing" do
    post user_password_path, params: {
      user: {
        email: "missing.user@example.com"
      }
    }

    assert_response :success
    assert_match "Email not found", @response.body
  end
end
