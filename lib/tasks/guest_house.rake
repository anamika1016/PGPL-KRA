namespace :guest_house do
  desc "Send one-day-before arrival reminders to guest house admins"
  task send_admin_arrival_reminders: :environment do
    GuestHouseNotificationService.send_due_admin_reminders
  end
end
