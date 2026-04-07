class AchievementRemark < ApplicationRecord
  belongs_to :achievement, optional: true
  belongs_to :activity, optional: true
end
