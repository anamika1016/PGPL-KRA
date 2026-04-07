class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user.present?

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
      (ed.l1_code == user.employee_code || ed.l1_employer_name == user.email) &&
      [ "pending", "l1_returned", "l1_approved", "l2_returned", "l2_approved" ].include?(ed.status)
    end

    can [ :approve, :return ], EmployeeDetail do |ed|
      (ed.l1_code == user.employee_code || ed.l1_employer_name == user.email) &&
      [ "pending", "l1_returned" ].include?(ed.status)
    end

    can :l1, EmployeeDetail do
      # User can access L1 view if they have any L1 assignments
      EmployeeDetail.where("l1_code = ? OR l1_employer_name = ?", user.employee_code, user.email).exists?
    end

    # L2 Permissions - Check if user's employee_code matches any l2_code OR email matches l2_employer_name
    can :read, EmployeeDetail do |ed|
      (ed.l2_code == user.employee_code || ed.l2_employer_name == user.email) &&
      [ "l1_approved", "l2_returned", "l2_approved" ].include?(ed.status)
    end

    can :show_l2, EmployeeDetail do |ed|
      ed.l2_code == user.employee_code || ed.l2_employer_name == user.email
    end

    can [ :l2_approve, :l2_return ], EmployeeDetail do |ed|
      (ed.l2_code == user.employee_code || ed.l2_employer_name == user.email) &&
      [ "l1_approved", "l2_returned" ].include?(ed.status)
    end

    # Edit L1 and L2 permissions - Only HOD can edit
    can [ :edit_l1, :edit_l2 ], EmployeeDetail do |ed|
      user.hod?
    end

    can :l2, EmployeeDetail do
      # User can access L2 view if they have any L2 assignments
      EmployeeDetail.where("l2_code = ? OR l2_employer_name = ?", user.employee_code, user.email).exists?
    end

    # UserDetail permissions
    if user.employee? || user.l1_employer? || user.l2_employer?
      # Users can read, edit, update, and destroy their own user details
      can [ :read, :edit, :update, :destroy ], UserDetail do |ud|
        ud.employee_detail&.employee_email == user.email
      end
    end
  end
end
