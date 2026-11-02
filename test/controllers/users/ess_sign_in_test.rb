# Builds its own records, so it does not load test_helper (its `fixtures :all` currently fails FK checks).
ENV["RAILS_ENV"] ||= "test"
require_relative "../../../config/environment"
require "rails/test_help"

class Users::EssSignInTest < ActionDispatch::IntegrationTest
  setup do
    @secret_was = ENV["ESS_SSO_SECRET"]
    ENV["ESS_SSO_SECRET"] = "ess-secret"
    @user = User.create!(email: "ess.sso@example.com", employee_code: "ESS777", role: "employee",
                         password: "secret123", password_confirmation: "secret123")
  end
  teardown { ENV["ESS_SSO_SECRET"] = @secret_was }

  # Same link ESS_PGPL ExternalAppLink.url_for builds
  def ess_link(code, to, expires_at: 2.minutes.from_now.to_i, secret: "ess-secret")
    sig = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{code}:#{to}:#{expires_at}")
    "/users/sign_in/#{code}?#{URI.encode_www_form(to: to, expires_at: expires_at, signature: sig)}"
  end

  test "signed ESS link signs in and opens the requested page" do
    { "training" => trainings_path, "help_desk" => help_desk_tickets_path, "guest_house" => guest_house_bookings_path }.each do |to, path|
      delete "/users/sign_out"
      get ess_link("ESS777", to)
      assert_redirected_to path
    end
    get trainings_path
    assert_response :success
  end

  test "employee code is matched case-insensitively" do
    get ess_link("ess777", "training")
    assert_redirected_to trainings_path
  end

  test "link without signature does not sign in" do
    get "/users/sign_in/ESS777?to=training"
    assert_redirected_to new_user_session_path
    get trainings_path
    assert_redirected_to new_user_session_path
  end

  test "wrong secret, expired link, unknown page or edited code are refused" do
    [ ess_link("ESS777", "training", secret: "other"),
      ess_link("ESS777", "training", expires_at: 1.minute.ago.to_i),
      ess_link("ESS777", "dashboard"),
      ess_link("ESS777", "training").sub("/ESS777?", "/OTHER1?") ].each do |url|
      get url
      assert_redirected_to new_user_session_path, url
    end
  end

  test "no secret configured → nobody is signed in" do
    ENV["ESS_SSO_SECRET"] = nil
    get ess_link("ESS777", "training")
    assert_redirected_to new_user_session_path
  end

  test "employee only in Employee List is provisioned on first ESS click" do
    EmployeeDetail.create!(employee_id: "NEW55", employee_name: "New Person", employee_email: "new55@example.com",
                           employee_code: "NEW55", department: "Project", post: "Executive")
    assert_difference("User.count", 1) { get ess_link("NEW55", "help_desk") }
    assert_redirected_to help_desk_tickets_path
  end
end
