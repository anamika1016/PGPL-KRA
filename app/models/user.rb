class User < ApplicationRecord
  DEFAULT_EMPLOYEE_PASSWORD = "123456".freeze

  # Devise modules for authentication
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :target_submissions
  has_one :employee_detail
  has_one_attached :profile_image
  has_many :l1_pulse_assessments, foreign_key: :l1_user_id, dependent: :destroy
  has_many :user_training_assignments, dependent: :destroy
  has_many :assigned_trainings, through: :user_training_assignments, source: :training
  has_many :user_training_progresses, dependent: :destroy

  ROLES = %w[employee hod admin l1_employer l2_employer]

  # Normalize employee codes so pgpl-002 and PGPL-002 behave the same everywhere.
  before_validation :sanitize_employee_code

  def sanitize_employee_code
    self.employee_code = normalize_employee_code(employee_code)
  end

  # Role helpers
  def employee?
    role == "employee"
  end

  def hod?
    role == "hod"
  end

  def admin?
    role == "admin"
  end

  def l1_employer?
    role == "l1_employer"
  end

  def l2_employer?
    role == "l2_employer"
  end

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    login = conditions.delete(:login)
    value = login.strip.downcase # 👈 Also strip and downcase login input
    where(conditions).where([ "lower(email) = :value OR lower(employee_code) = :value", { value: value } ]).first
  end

  def self.find_by_email_or_employee_code(email:, employee_code:)
    normalized_code = employee_code.to_s.strip
    normalized_email = email.to_s.strip.downcase

    if normalized_code.present?
      user = where("lower(employee_code) = ?", normalized_code.downcase).first
      return user if user
    end

    return nil if normalized_email.blank?

    where("lower(email) = ?", normalized_email).first
  end

  def self.provision_from_employee_detail(employee_detail)
    return if employee_detail.blank? || employee_detail.employee_code.blank?

    existing_user = find_by_email_or_employee_code(
      email: employee_detail.employee_email,
      employee_code: employee_detail.employee_code
    )

    user = existing_user || new
    user.email = provision_login_email_for(employee_detail, existing_user)
    user.employee_code = employee_detail.employee_code
    user.role = user.role.presence || "employee"

    if user.new_record?
      user.password = DEFAULT_EMPLOYEE_PASSWORD
      user.password_confirmation = DEFAULT_EMPLOYEE_PASSWORD
    end

    user.save! if user.new_record? || user.changed?

    if employee_detail.user_id != user.id
      employee_detail.update!(user: user)
    end

    user
  end

  def self.provision_login_email_for(employee_detail, existing_user = nil)
    return existing_user.email if existing_user&.email.present?
    return employee_detail.employee_email if employee_detail.employee_email.present?

    base_local_part = employee_detail.employee_code.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    base_local_part = "employee" if base_local_part.blank?
    generated_email = "#{base_local_part}@papl.local"
    suffix = 1

    while where.not(id: existing_user&.id).exists?(email: generated_email)
      suffix += 1
      generated_email = "#{base_local_part}_#{suffix}@papl.local"
    end

    generated_email
  end

  def name
    email
  end

  private

  def normalize_employee_code(value)
    value.to_s.strip.upcase.presence
  end
end
