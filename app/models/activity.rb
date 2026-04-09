class Activity < ApplicationRecord
  belongs_to :department

  has_many :user_details

  validates :financial_year, presence: true

  before_validation :assign_default_financial_year

  scope :for_financial_year, ->(financial_year) {
    normalized_year = UserDetail.normalize_financial_year(financial_year).presence || UserDetail.current_financial_year
    where(financial_year: normalized_year)
  }

  private

  def assign_default_financial_year
    self.financial_year = UserDetail.normalize_financial_year(financial_year).presence ||
                          department&.financial_year.presence ||
                          UserDetail.current_financial_year
  end
end
