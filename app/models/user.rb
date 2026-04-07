class User < ApplicationRecord
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

  # Auto-strip employee_code before save
  before_validation :sanitize_employee_code

  def sanitize_employee_code
    self.employee_code = employee_code.strip if employee_code.present?
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

  def name
    email
  end
end
