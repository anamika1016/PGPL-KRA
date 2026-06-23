class GuestHouseNotificationService
  def self.booking_created(booking)
    message = "Your guest house booking #{booking.booking_reference_label} for #{booking.guest_house.name} from #{booking.booking_date.strftime('%d %b %Y')} #{booking.checkin_label} to #{booking.effective_checkout_date.strftime('%d %b %Y')} #{booking.checkout_label} is confirmed and pending admin acceptance. ASA"
    send_booking_sms(booking, message)
    notify_user(
      booking,
      event_type: "booking_submitted",
      title: "Booking submitted",
      message: "#{booking.booking_reference_label} is waiting for admin acceptance.",
      actor: booking.user
    )
    notify_admins(
      booking,
      event_type: "new_booking",
      title: "New guest house booking",
      message: "#{booking.requester_name} submitted #{booking.booking_reference_label} for #{booking.guest_house.name}.",
      actor: booking.user
    )
  end

  def self.booking_accepted(booking)
    message = "Your guest house booking #{booking.booking_reference_label} has been accepted. Please carry the printout at check-in. ASA"
    send_booking_sms(booking, message)
    notify_user(booking, event_type: "booking_accepted", title: "Booking accepted", message: "#{booking.booking_reference_label} has been accepted.", actor: booking.accepted_by)
  end

  def self.booking_rejected(booking)
    message = "Your guest house booking #{booking.booking_reference_label} has been rejected. Remark: #{booking.rejection_remark.presence || booking.admin_remark.presence || 'Not provided'}. ASA"
    send_booking_sms(booking, message)
    notify_user(booking, event_type: "booking_rejected", title: "Booking rejected", message: "#{booking.booking_reference_label} was rejected. #{booking.rejection_remark.presence || booking.admin_remark.presence}", actor: booking.accepted_by)
  end

  def self.booking_cancelled(booking, actor:)
    message = "#{booking.booking_reference_label} was cancelled by #{actor.display_name}. Reason: #{booking.cancellation_reason}"
    send_booking_sms(booking, "Guest house booking #{booking.booking_reference_label} has been cancelled. Reason: #{booking.cancellation_reason}. ASA")
    notify_user(booking, event_type: "booking_cancelled", title: "Booking cancelled", message: message, actor: actor) unless actor.id == booking.user_id
    notify_admins(booking, event_type: "booking_cancelled", title: "Booking cancelled", message: message, actor: actor)
  end

  def self.availability_opened(waitlist, cancelled_booking:, actor:)
    message = availability_message(waitlist)
    GuestHouseNotification.create!(
      user: waitlist.user,
      guest_house_booking: cancelled_booking,
      guest_house_waitlist: waitlist,
      actor: actor,
      event_type: "availability_opened",
      title: "Guest house slot available",
      message: message
    )
    mobile = waitlist.user.mapped_employee_detail&.mobile_number
    SmsService.send_sms(mobile, "Guest house slot is now available for #{waitlist.booking_date.strftime('%d %b %Y')} to #{waitlist.checkout_date.strftime('%d %b %Y')}. Please book promptly. ASA") if mobile.present?
  rescue StandardError => e
    Rails.logger.warn("Guest house availability notification failed for waitlist #{waitlist.id}: #{e.message}")
  end

  def self.availability_message(waitlist)
    alternatives = waitlist.alternative_dates.map { |date| date.strftime("%d %b %Y") }
    alternative_text = alternatives.present? ? " Alternative check-in dates: #{alternatives.to_sentence}." : ""
    "A suitable #{waitlist.room_type.humanize.downcase} room is now available at #{waitlist.guest_house.name} from #{waitlist.booking_date.strftime('%d %b %Y')} to #{waitlist.checkout_date.strftime('%d %b %Y')}.#{alternative_text} Availability is not held; book promptly."
  end

  def self.checkin_completed(booking)
    message = "Check-in completed for guest house booking #{booking.booking_reference_label}. Stay: #{booking.guest_house.name}. ASA"
    send_booking_sms(booking, message)
    notify_user(booking, event_type: "checkin_completed", title: "Check-in completed", message: "Check-in is complete for #{booking.booking_reference_label}.", actor: booking.accepted_by)
    booking.update_column(:checkin_sms_sent_at, Time.current) if booking.has_attribute?(:checkin_sms_sent_at)
  end

  def self.checkout_extended(booking, actor:)
    notify_user(booking, event_type: "checkout_extended", title: "Checkout extended", message: "Checkout for #{booking.booking_reference_label} is extended to #{booking.effective_checkout_date.strftime('%d %b %Y')} #{booking.effective_checkout_time&.strftime('%I:%M %p')}.", actor: actor)
  end

  def self.checkout_completed(booking, actor:)
    notify_user(booking, event_type: "checkout_completed", title: "Checkout and bill completed", message: "#{booking.booking_reference_label} is checked out. Bill amount: Rs. #{format('%.2f', booking.invoice_total)}.", actor: actor)
  end

  def self.occupant_checked_in(occupant, actor:)
    booking = occupant.guest_house_booking
    notify_user(booking, event_type: "occupant_checked_in", title: "#{occupant.full_name} checked in", message: "Individual check-in completed for #{occupant.full_name} under #{booking.booking_reference_label}.", actor: actor)
  end

  def self.occupant_accepted(occupant, actor:)
    booking = occupant.guest_house_booking
    notify_user(booking, event_type: "occupant_accepted", title: "#{occupant.full_name} accepted", message: "#{occupant.full_name} was accepted under #{booking.booking_reference_label}.", actor: actor)
  end

  def self.occupant_rejected(occupant, actor:)
    booking = occupant.guest_house_booking
    notify_user(booking, event_type: "occupant_rejected", title: "#{occupant.full_name} rejected", message: "#{occupant.full_name} was rejected under #{booking.booking_reference_label}. Reason: #{occupant.rejection_remark}", actor: actor)
  end

  def self.occupant_payment_updated(occupant, actor:)
    booking = occupant.guest_house_booking
    notify_user(booking, event_type: "occupant_payment_updated", title: "#{occupant.full_name} payment updated", message: "Payment for #{occupant.full_name}'s Rs. #{format('%.2f', occupant.total_bill_amount)} bill is now #{occupant.payment_status.humanize}.", actor: actor)
  end

  def self.occupant_checked_out(occupant, actor:)
    booking = occupant.guest_house_booking
    notify_user(booking, event_type: "occupant_checked_out", title: "#{occupant.full_name} checked out", message: "Individual checkout completed for #{occupant.full_name} under #{booking.booking_reference_label}.", actor: actor)
  end

  def self.payment_generated(booking, actor:)
    notify_user(booking, event_type: "payment_generated", title: "Payment requested", message: "Payment of Rs. #{format('%.2f', booking.invoice_total)} is ready for #{booking.booking_reference_label}.", actor: actor)
  end

  def self.payment_updated(booking, actor:)
    notify_user(booking, event_type: "payment_updated", title: "Payment status updated", message: "Payment for #{booking.booking_reference_label} is now #{booking.payment_status.humanize}.", actor: actor)
  end

  def self.complaint_submitted(booking, actor:)
    notify_admins(booking, event_type: "complaint_submitted", title: "Guest complaint submitted", message: "A complaint was submitted for #{booking.booking_reference_label}.", actor: actor)
  end

  def self.feedback_submitted(booking, actor:)
    notify_admins(booking, event_type: "feedback_submitted", title: "Guest feedback received", message: "#{booking.booking_reference_label} received a #{booking.feedback_rating}/5 rating.", actor: actor)
  end

  def self.admin_arrival_reminder(booking)
    admin_mobile = booking.guest_house.manager_user&.mapped_employee_detail&.mobile_number
    return if admin_mobile.blank?

    message = "Reminder: Guest #{booking.requester_name} will arrive for #{booking.guest_house.name} on #{booking.booking_date.strftime('%d %b %Y')} #{booking.checkin_label}. Ref #{booking.booking_reference_label}. ASA"
    SmsService.send_sms(admin_mobile, message)
    booking.update_column(:admin_reminder_sent_at, Time.current) if booking.has_attribute?(:admin_reminder_sent_at)
  rescue StandardError => e
    Rails.logger.warn("Guest house admin reminder SMS failed for booking #{booking.id}: #{e.message}")
  end

  def self.send_due_admin_reminders
    GuestHouseBooking.accepted
                     .where(admin_reminder_sent_at: nil, booking_date: Date.current + 1.day)
                     .includes(:guest_house, user: :employee_detail)
                     .find_each { |booking| admin_arrival_reminder(booking) }
  end

  def self.send_booking_sms(booking, message)
    mobile = booking.requester_mobile
    return if mobile.blank?

    SmsService.send_sms(mobile, message)
  rescue StandardError => e
    Rails.logger.warn("Guest house SMS failed for booking #{booking.id}: #{e.message}")
  end

  def self.notify_user(booking, event_type:, title:, message:, actor: nil)
    create_in_app_notification(user: booking.user, booking: booking, event_type: event_type, title: title, message: message, actor: actor)
  end

  def self.notify_admins(booking, event_type:, title:, message:, actor: nil)
    manager = booking.guest_house.manager_user
    recipients = ([ manager ] + User.where(role: "hod").to_a).compact.uniq
    recipients.reject { |user| user.id == actor&.id }.each do |user|
      create_in_app_notification(user: user, booking: booking, event_type: event_type, title: title, message: message, actor: actor)
    end
  end

  def self.create_in_app_notification(user:, booking:, event_type:, title:, message:, actor: nil)
    return if user.blank?

    GuestHouseNotification.create!(
      user: user,
      guest_house_booking: booking,
      actor: actor,
      event_type: event_type,
      title: title,
      message: message
    )
  rescue StandardError => e
    Rails.logger.warn("Guest house in-app notification failed for booking #{booking.id}: #{e.message}")
  end
end
