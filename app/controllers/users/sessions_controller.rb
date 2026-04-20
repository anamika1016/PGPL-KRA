class Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, only: [ :create ] # only for testing, enable CSRF later

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
end
