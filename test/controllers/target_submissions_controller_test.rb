require "test_helper"

class TargetSubmissionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get target_submissions_new_url
    assert_response :success
  end

  test "should get edit" do
    get target_submissions_edit_url
    assert_response :success
  end

  test "should get index" do
    get target_submissions_index_url
    assert_response :success
  end
end
