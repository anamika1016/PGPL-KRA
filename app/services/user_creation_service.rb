class UserCreationService
  DEFAULT_PASSWORD = "123456"
  DEFAULT_ROLE = "employee"

  def self.create_user_from_employee_data(employee_data, existing_users_cache = nil)
    new.create_user_from_employee_data(employee_data, existing_users_cache)
  end

  def create_user_from_employee_data(employee_data, existing_users_cache = nil)
    return { success: false, message: "Employee data is required" } if employee_data.blank?

    # Extract required fields
    email = employee_data[:employee_email] || employee_data["employee_email"]
    employee_code = employee_data[:employee_code] || employee_data["employee_code"]
    employee_name = employee_data[:employee_name] || employee_data["employee_name"]

    # Require both email AND employee_code for account creation
    # But allow updates if user already exists with either email or employee_code
    if email.blank? && employee_code.blank?
      return { success: false, message: "Email and Employee Code are required" }
    end

    # Use cache if provided, otherwise query database
    existing_user = nil
    if existing_users_cache
      # Use pre-loaded cache for faster lookup
      email_lower = email.to_s.strip.downcase if email.present?
      employee_code_clean = employee_code.to_s.strip if employee_code.present?

      existing_user = existing_users_cache[:by_email][email_lower] if email_lower.present?
      existing_user ||= existing_users_cache[:by_code][employee_code_clean] if employee_code_clean.present? && existing_user.nil?
    else
      # Fallback to individual queries (slower, but works)
      if email.present?
        existing_user = User.find_by(email: email)
      end
      if existing_user.nil? && employee_code.present?
        existing_user = User.find_by(employee_code: employee_code)
      end
    end

    if existing_user
      # Update existing user with new data if available
      update_fields = {}
      update_fields[:email] = email if email.present? && existing_user.email != email
      update_fields[:employee_code] = employee_code if employee_code.present? && existing_user.employee_code != employee_code

      if update_fields.any?
        existing_user.update!(update_fields)
        Rails.logger.info "Updated existing user: #{existing_user.email} with new data"
      end

      return { success: true, user: existing_user, message: "User already exists and updated" }
    end

    # Only create new user if both email and employee_code are present
    if email.blank? || employee_code.blank?
      return { success: false, message: "Cannot create account: Both email and employee_code are required" }
    end

    begin
      # Create new user with default password and employee role
      user = User.create!(
        email: email,
        employee_code: employee_code,
        password: DEFAULT_PASSWORD,
        password_confirmation: DEFAULT_PASSWORD,
        role: DEFAULT_ROLE
      )

      Rails.logger.info "Created user: #{user.email} with employee code: #{user.employee_code}"
      { success: true, user: user, message: "User created successfully with default password '#{DEFAULT_PASSWORD}'" }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create user: #{e.message}"
      { success: false, message: "Failed to create user: #{e.message}" }
    rescue => e
      Rails.logger.error "Unexpected error creating user: #{e.message}"
      { success: false, message: "Unexpected error: #{e.message}" }
    end
  end

  # Optimized method to build cache of existing users for bulk operations
  def self.build_existing_users_cache
    users = User.select(:id, :email, :employee_code).all
    by_email = {}
    by_code = {}

    users.each do |user|
      if user.email.present?
        email_key = user.email.to_s.strip.downcase
        by_email[email_key] = user unless email_key.blank?
      end
      if user.employee_code.present?
        code_key = user.employee_code.to_s.strip
        by_code[code_key] = user unless code_key.blank?
      end
    end

    {
      by_email: by_email,
      by_code: by_code
    }
  end

  def self.create_users_from_excel_data(excel_data)
    new.create_users_from_excel_data(excel_data)
  end

  def create_users_from_excel_data(excel_data)
    results = {
      created: [],
      existing: [],
      errors: []
    }

    excel_data.each_with_index do |row_data, index|
      result = create_user_from_employee_data(row_data)

      if result[:success]
        if result[:message] == "User already exists"
          results[:existing] << { row: index + 2, data: row_data, user: result[:user] }
        else
          results[:created] << { row: index + 2, data: row_data, user: result[:user] }
        end
      else
        results[:errors] << { row: index + 2, data: row_data, error: result[:message] }
      end
    end

    results
  end
end
