class GuestHouseNotificationsController < ApplicationController
  before_action :set_notification, only: :open

  def index
    @notifications = current_user.guest_house_notifications
                                 .includes(:guest_house_booking, :guest_house_waitlist, :actor)
                                 .recent_first
                                 .limit(100)
    @unread_count = current_user.guest_house_notifications.unread.count
  end

  def open
    @notification.mark_read!
    if @notification.guest_house_waitlist_id.present?
      redirect_to guest_house_bookings_path(waitlist_id: @notification.guest_house_waitlist_id)
    else
      redirect_to guest_house_booking_path(@notification.guest_house_booking)
    end
  end

  def mark_all_read
    current_user.guest_house_notifications.unread.update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to guest_house_notifications_path, notice: "All guest house notifications marked as read."
  end

  private

  def set_notification
    @notification = current_user.guest_house_notifications.find(params[:id])
  end
end
