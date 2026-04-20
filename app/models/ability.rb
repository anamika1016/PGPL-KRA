class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.present?

    normalized_email = normalize_lookup_value(user.email)
    normalized_codes = normalized_user_codes(user)

    if user.hod?
      can :manage, :all  # HOD gets full access to all models
      return  # Early return for HOD to avoid duplicate permissions
    end

    # Basic employee permissions
    if user.employee? || user.l1_employer? || user.l2_employer?
      can :read, EmployeeDetail, employee_email: user.email
      can :read, EmployeeDetail, employee_code: user.employee_code
    end

    # L1 Permissions - Check if user's employee_code matches any l1_code OR email matches l1_employer_name
    can :read, EmployeeDetail do |ed|
      (normalized_codes.include?(normalize_lookup_value(ed.l1_code)) || normalize_lookup_value(ed.l1_employer_name) == normalized_email) &&
      [ "pending", "l1_returned", "l1_approved", "l2_returned", "l2_approved" ].include?(ed.status)
    end

    can [ :approve, :return ], EmployeeDetail do |ed|
      (normalized_codes.include?(normalize_lookup_value(ed.l1_code)) || normalize_lookup_value(ed.l1_employer_name) == normalized_email) &&
      [ "pending", "l1_returned" ].include?(ed.status)
    end

    can :l1, EmployeeDetail do
      # User can access L1 view if they have any L1 assignments
      EmployeeDetail.where(
        "LOWER(BTRIM(COALESCE(l1_code, ''))) IN (?) OR LOWER(BTRIM(COALESCE(l1_employer_name, ''))) = ?",
        normalized_codes,
        normalized_email
      ).exists?
    end

    # L2 Permissions - Check if user's employee_code matches any l2_code OR email matches l2_employer_name
    can :read, EmployeeDetail do |ed|
      (normalized_codes.include?(normalize_lookup_value(ed.l2_code)) || normalize_lookup_value(ed.l2_employer_name) == normalized_email) &&
      [ "l1_approved", "l2_returned", "l2_approved" ].include?(ed.status)
    end

    can :show_l2, EmployeeDetail do |ed|
      normalized_codes.include?(normalize_lookup_value(ed.l2_code)) || normalize_lookup_value(ed.l2_employer_name) == normalized_email
    end

    can [ :l2_approve, :l2_return ], EmployeeDetail do |ed|
      (normalized_codes.include?(normalize_lookup_value(ed.l2_code)) || normalize_lookup_value(ed.l2_employer_name) == normalized_email) &&
      [ "l1_approved", "l2_returned" ].include?(ed.status)
    end

    # Edit L1 and L2 permissions - Only HOD can edit
    can [ :edit_l1, :edit_l2 ], EmployeeDetail do |ed|
      user.hod?
    end

    can :l2, EmployeeDetail do
      # User can access L2 view if they have any L2 assignments
      EmployeeDetail.where(
        "LOWER(BTRIM(COALESCE(l2_code, ''))) IN (?) OR LOWER(BTRIM(COALESCE(l2_employer_name, ''))) = ?",
        normalized_codes,
        normalized_email
      ).exists?
    end

    # UserDetail permissions
    if user.employee? || user.l1_employer? || user.l2_employer?
      # Users can read, edit, update, and destroy their own user details
      can [ :read, :edit, :update, :destroy ], UserDetail do |ud|
        ud.employee_detail&.employee_email == user.email
      end
    end
  end

  private

  def normalize_lookup_value(value)
    value.to_s.strip.downcase.presence
  end

  def normalized_user_codes(user)
    employee_detail = user.employee_detail || EmployeeDetail.find_by("LOWER(BTRIM(COALESCE(employee_email, ''))) = ?", normalize_lookup_value(user.email))

    [
      user.employee_code,
      employee_detail&.employee_code
    ].filter_map { |code| normalize_lookup_value(code) }.uniq
  end
end
