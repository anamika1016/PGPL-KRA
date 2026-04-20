class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [ :employee_code, :role ])
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :employee_code, :role ])
  end

  # Override Devise's after_sign_in_path_for to always redirect to dashboard
  def after_sign_in_path_for(resource)
    dashboard_path
  end

  def has_l1_responsibilities?
    return true if current_user.hod?
    EmployeeDetail.exists?(l1_code: current_user.employee_code) ||
    EmployeeDetail.exists?(l1_employer_name: current_user.email)
  end

  def has_l2_responsibilities?
    return true if current_user.hod?
    EmployeeDetail.exists?(l2_code: current_user.employee_code) ||
    EmployeeDetail.exists?(l2_employer_name: current_user.email)
  end

  def selected_financial_year
    @selected_financial_year ||= UserDetail.normalize_financial_year(params[:financial_year]).presence ||
                                 UserDetail.current_financial_year
  end

  def available_financial_years
    UserDetail.available_financial_years
  end

  helper_method :has_l1_responsibilities?, :has_l2_responsibilities?,
                :selected_financial_year, :available_financial_years
end
