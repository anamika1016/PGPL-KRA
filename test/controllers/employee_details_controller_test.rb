require "test_helper"

class EmployeeDetailsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get employee_details_index_url
    assert_response :success
  end

  test "should get new" do
    get employee_details_new_url
    assert_response :success
  end

  test "should get edit" do
    get employee_details_edit_url
    assert_response :success
  end
end
