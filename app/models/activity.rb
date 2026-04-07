class Activity < ApplicationRecord
  belongs_to :department

  has_many :user_details
end
