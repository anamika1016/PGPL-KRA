class ApplicationController < ActionController::Base
  before_action :authenticate_user_for_request!
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

  def helpdesk_reviewer?
    return false if current_user.blank?
    return true if current_user.hod?

    HelpdeskEscalationLevel.where(user_id: current_user.id).exists? ||
      HelpdeskEscalationMatrix.where(
        "l1_user_id = :user_id OR l2_user_id = :user_id",
        user_id: current_user.id
      ).exists?
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

  helper_method :has_l1_responsibilities?, :has_l2_responsibilities?, :helpdesk_reviewer?,
                :selected_financial_year, :available_financial_years

  protected

  def helpdesk_selectable_departments
    Department
      .where.not(department_type: [ nil, "" ])
      .select(:id, :department_type)
      .order(Arel.sql("LOWER(department_type) ASC"))
  end

  def helpdesk_employee_option_users
    EmployeeDetail
      .order(Arel.sql("LOWER(COALESCE(employee_name, '')), LOWER(COALESCE(employee_code, ''))"))
      .filter_map { |employee_detail| helpdesk_user_for_employee_detail(employee_detail) }
      .uniq { |user| user.id }
  end

  def helpdesk_user_for_employee_detail(employee_detail)
    return if employee_detail.blank?

    employee_detail.user ||
      User.find_by_email_or_employee_code(
        email: employee_detail.employee_email,
        employee_code: employee_detail.employee_code
      ) ||
      User.provision_from_employee_detail(employee_detail)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "Could not provision helpdesk user for employee detail #{employee_detail.id}: #{e.message}"
    nil
  end

  private

  def authenticate_user_for_request!
    return if devise_controller? || user_signed_in?

    if request.format.pdf?
      store_location_for(:user, request.fullpath)
      redirect_to new_user_session_path, alert: "Please sign in to view or download this PDF."
    else
      authenticate_user!
    end
  end

  def sync_helpdesk_departments_from_employee_details(names)
    existing_names = Department.pluck(:department_type).map { |name| name.to_s.strip.downcase }
    names.each do |name|
      normalized_name = name.downcase
      next if existing_names.include?(normalized_name)

      Department.create!(department_type: name, financial_year: selected_financial_year)
      existing_names << normalized_name
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "Could not sync helpdesk department '#{name}' from employee details: #{e.message}"
    end
  end

  def helpdesk_vertical_names
    return [] unless EmployeeDetail.column_names.include?("vertical")

    EmployeeDetail
      .where.not(vertical: [ nil, "" ])
      .distinct
      .pluck(:vertical)
      .map { |name| name.to_s.strip }
      .reject(&:blank?)
      .uniq { |name| name.downcase }
  end

  def normalize_lookup_value(value)
    value.to_s.strip.downcase.presence
  end

  def employee_detail_scope_for_current_user
    return EmployeeDetail.none if normalized_current_employee_codes.empty? && normalized_current_user_email.blank?

    EmployeeDetail.all
  end
end
