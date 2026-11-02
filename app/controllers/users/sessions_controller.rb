require "openssl"

class Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, only: [ :create ] # only for testing, enable CSRF later

  # Pages ESS (hr.asaindia.org/pgpl → IT Tools) may open directly after its signed sign-in link.
  ESS_LANDING_PAGES = {
    "guest_house" => :guest_house_bookings_path,
    "help_desk"   => :help_desk_tickets_path,
    "training"    => :trainings_path
  }.freeze

  # GET /users/sign_in/:employee_code?to=<page>&expires_at=<unix>&signature=<hex>
  # signature = HMAC-SHA256(ESS_SSO_SECRET, "<employee_code>:<to>:<expires_at>") – built by ESS (ExternalAppLink).
  # Only a valid, unexpired signed link signs in; anything else goes to the normal login page.
  def employee_code_sign_in
    code = params[:employee_code].to_s.strip

    unless valid_ess_sign_in_link?(code)
      sign_out(resource_name) if user_signed_in?
      redirect_to new_session_path(resource_name), alert: "Invalid or expired sign in link. Please sign in again." and return
    end

    user = User.find_by_email_or_employee_code(email: nil, employee_code: code) ||
      User.provision_from_employee_detail(EmployeeDetail.where("lower(employee_code) = ?", code.downcase).first)

    if user.nil?
      sign_out(resource_name) if user_signed_in?
      redirect_to new_session_path(resource_name), alert: "No employee account found for that employee code." and return
    end

    sign_out(resource_name) if user_signed_in? && current_user != user
    sign_in(resource_name, user)
    redirect_to public_send(ESS_LANDING_PAGES[params[:to].to_s])
  end

  def create
    submitted_email = params.dig(:user, :email).to_s.strip
    submitted_password = params.dig(:user, :password).to_s
    submitted_code = params.dig(:user, :employee_code).to_s.strip

    if submitted_code.blank?
      flash[:alert] = "Employee code is required."
      redirect_to new_session_path(resource_name) and return
    end

    user = User.find_by_email_or_employee_code(email: submitted_email, employee_code: submitted_code)
    employee_detail = EmployeeDetail.where("lower(employee_code) = ?", submitted_code.downcase).first

    if user.nil? && submitted_password == User::DEFAULT_EMPLOYEE_PASSWORD
      user = User.provision_from_employee_detail(employee_detail) if employee_detail.present?
    end

    if user.nil?
      flash[:alert] = "No employee account found for that employee code."
      redirect_to new_session_path(resource_name) and return
    end

    unless user.valid_password?(submitted_password)
      flash[:alert] = "Incorrect password."
      redirect_to new_session_path(resource_name) and return
    end

    unless user.employee_code.to_s.strip.casecmp?(submitted_code)
      flash[:alert] = "Incorrect employee code."
      redirect_to new_session_path(resource_name) and return
    end

    if employee_detail.present? && employee_detail.employee_code.to_s.strip.present? &&
       !user.employee_code.to_s.strip.casecmp?(employee_detail.employee_code.to_s.strip)
      user.update(employee_code: employee_detail.employee_code)
    end

    if employee_detail.present? && employee_detail.user_id != user.id
      employee_detail.update(user: user)
    end

    sign_in(resource_name, user)
    redirect_to after_sign_in_path_for(user)
  end

  private

  def valid_ess_sign_in_link?(code)
    page = params[:to].to_s
    expires_at = params[:expires_at].to_s
    signature = params[:signature].to_s
    secret = ENV["ESS_SSO_SECRET"].presence || Rails.application.credentials.dig(:ess_sso_secret).presence

    return false if code.blank? || secret.blank? || signature.blank? || !ESS_LANDING_PAGES.key?(page)
    return false if Time.at(Integer(expires_at)) < Time.current

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{code}:#{page}:#{expires_at}")
    ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  rescue ArgumentError, TypeError
    false
  end
end
