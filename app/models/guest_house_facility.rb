class GuestHouseFacility < ApplicationRecord
  belongs_to :guest_house

  before_validation :normalize_name

  validates :name, presence: true, uniqueness: { scope: :guest_house_id, case_sensitive: false }
  validates :rate, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { joins(:guest_house).order(Arel.sql("lower(guest_houses.name) asc, lower(guest_house_facilities.name) asc")) }

  def display_name
    "#{guest_house.name} - #{name} (Rs. #{format('%.2f', rate || 0)})"
  end

  private

  def normalize_name
    self.name = name.to_s.strip.squeeze(" ")
  end
end
