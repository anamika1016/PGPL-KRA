class Training < ApplicationRecord
  has_many_attached :files
  has_many :user_training_progresses, dependent: :destroy
  has_many :user_training_assignments, dependent: :destroy
  has_many :assigned_users, through: :user_training_assignments, source: :user
  has_many :training_questions, dependent: :destroy
  accepts_nested_attributes_for :training_questions, allow_destroy: true

  validates :title, presence: true
  validates :duration, presence: true
  validates :month, presence: true
  validates :year, presence: true

  def month_name
    Date::MONTHNAMES[month.to_i]
  end

  scope :active, -> { where(status: true) }
  scope :inactive, -> { where(status: false) }
end
