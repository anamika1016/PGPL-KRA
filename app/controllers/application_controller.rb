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
    employee_detail_scope_for_current_user.exists?(
      [
        "LOWER(BTRIM(COALESCE(l1_code, ''))) IN (?) OR LOWER(BTRIM(COALESCE(l1_employer_name, ''))) = ?",
        normalized_current_employee_codes,
        normalized_current_user_email
      ]
    )
  end

  def has_l2_responsibilities?
    return true if current_user.hod?
    employee_detail_scope_for_current_user.exists?(
      [
        "LOWER(BTRIM(COALESCE(l2_code, ''))) IN (?) OR LOWER(BTRIM(COALESCE(l2_employer_name, ''))) = ?",
        normalized_current_employee_codes,
        normalized_current_user_email
      ]
    )
  end

  def selected_financial_year
    @selected_financial_year ||= UserDetail.normalize_financial_year(params[:financial_year]).presence ||
                                 UserDetail.current_financial_year
  end

  def available_financial_years
    UserDetail.available_financial_years
  end

  def current_employee_detail_record
    @current_employee_detail_record ||= current_employee_detail_records.order(:id).first
  end

  def current_employee_detail_records
    @current_employee_detail_records ||= begin
      scope = EmployeeDetail.all
      conditions = []
      values = []

      if current_user.id.present?
        conditions << "user_id = ?"
        values << current_user.id
      end

      if normalized_current_employee_codes.any?
        conditions << "LOWER(BTRIM(COALESCE(employee_code, ''))) IN (?)"
        values << normalized_current_employee_codes
      end

      if normalized_current_user_email.present?
        conditions << "LOWER(BTRIM(COALESCE(employee_email, ''))) = ?"
        values << normalized_current_user_email
      end

      if conditions.any?
        scope.where([ conditions.join(" OR "), *values ]).distinct
      else
        EmployeeDetail.none
      end
    end
  end

  def current_employee_detail_ids
    @current_employee_detail_ids ||= current_employee_detail_records.pluck(:id)
  end

  def normalized_current_employee_codes
    @normalized_current_employee_codes ||= [
      current_user.employee_code,
      current_user.employee_detail&.employee_code
    ].filter_map { |code| normalize_lookup_value(code) }.uniq
  end

  def normalized_current_user_email
    @normalized_current_user_email ||= normalize_lookup_value(current_user.email)
  end

  helper_method :has_l1_responsibilities?, :has_l2_responsibilities?,
                :selected_financial_year, :available_financial_years

  private

  def normalize_lookup_value(value)
    value.to_s.strip.downcase.presence
  end

  def employee_detail_scope_for_current_user
    return EmployeeDetail.none if normalized_current_employee_codes.empty? && normalized_current_user_email.blank?

    current_employee_detail_records
  end
end
