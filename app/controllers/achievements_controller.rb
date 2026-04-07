class AchievementsController < ApplicationController
  def new
    @user_detail = UserDetail.find(params[:user_detail_id])
    @months = %w[april may june july august september october november december january february march]
    @existing_achievements = @user_detail.achievements.index_by(&:month)
  end

  def create
    @user_detail = UserDetail.find(params[:user_detail_id])

    achievements_params.each do |month, achievement|
      next if achievement.blank?

      a = @user_detail.achievements.find_or_initialize_by(month: month)
      a.achievement = achievement
      # FIXED: Ensure status is set to pending for quarterly consistency
      a.status = "pending"
      a.save
    end

    redirect_to user_detail_path(@user_detail), notice: "Achievements submitted successfully."
  end

  private

  def achievements_params
    params.require(:achievements).permit(
      *%w[april may june july august september october november december january february march]
    )
  end
end
