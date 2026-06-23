class GuestHouseBookingsController < ApplicationController
  before_action :load_guest_house_context, only: [ :index, :create ]
  before_action :set_booking, only: [ :show, :destroy, :accept, :reject, :cancel, :check_in, :checkout, :receipt, :submit_complaint, :submit_feedback, :generate_payment, :upload_payment ]
  before_action :ensure_booking_owner_or_admin!, only: [ :show, :cancel, :receipt, :submit_complaint, :submit_feedback ]
  before_action :ensure_hod!, only: [ :destroy ]
  before_action :ensure_guest_house_admin!, only: [ :accept, :reject, :check_in, :checkout, :generate_payment, :upload_payment ]
  before_action :ensure_confirmed!, only: [ :accept ]
  before_action :ensure_rejectable!, only: [ :reject ]
  before_action :ensure_accepted!, only: [ :check_in ]
  before_action :ensure_checked_in!, only: [ :checkout ]
  before_action :ensure_checked_out!, only: [ :generate_payment, :upload_payment ]

  def index
    @guest_house_booking = current_user.guest_house_bookings.new
    waitlist = current_user.guest_house_waitlists.where(status: %w[waiting notified]).find_by(id: params[:waitlist_id])
    if waitlist
      @guest_house_booking.assign_attributes(
        guest_house: waitlist.guest_house,
        booking_date: waitlist.booking_date,
        checkin_time: waitlist.checkin_time,
        checkout_date: waitlist.checkout_date,
        checkout_time: waitlist.checkout_time,
        rooms_count: waitlist.rooms_count,
        room_type: waitlist.room_type,
        guest_gender: waitlist.guest_gender,
        booking_for: waitlist.booking_for
      )
      if @guest_house_booking.external_booking?
        waitlist.occupant_gender_counts.each do |gender, count|
          count.to_i.times { @guest_house_booking.guest_house_booking_guests.build(gender: gender) }
        end
      end
      flash.now[:notice] = "A matching slot is available. Please confirm the guest details and submit promptly."
    else
      @guest_house_booking.booking_for = nil
      @guest_house_booking.guest_gender = nil
    end
    @single_room_eligible = @guest_house_booking.single_room_eligible?
    build_guest_detail_rows
  end

  def records
    if current_user.hod?
      bookings = GuestHouseBooking.all
      @records_title = "All Booking Records"
      @records_subtitle = "Bookings submitted for every guest house."
    elsif current_user.managed_guest_houses.exists?
      bookings = GuestHouseBooking.for_admin(current_user)
      @records_title = "Guest House Booking Records"
      @records_subtitle = "All bookings for your assigned guest house."
    else
      bookings = GuestHouseBooking.submitted_by(current_user)
      @records_title = "My Booking Records"
      @records_subtitle = "All guest house bookings submitted from your account."
    end

    @record_bookings = bookings.includes(:guest_house, :guest_house_booking_guests, user: :employee_detail, accepted_by: :employee_detail)
                               .recent_first
    @record_status_counts = @record_bookings.unscope(:order).group(:status).count
    @facilities_by_house = {}
  end

  def create
    @guest_house_booking = current_user.guest_house_bookings.new(booking_params)
    @guest_house_booking.status = "confirmed"

    saved = if @guest_house_booking.guest_house.present?
              @guest_house_booking.guest_house.with_lock { @guest_house_booking.save }
            else
              @guest_house_booking.save
            end

    if saved
      GuestHouseWaitlist.fulfill_matching!(@guest_house_booking)
      redirect_to guest_house_booking_path(@guest_house_booking), notice: "Booking confirmed successfully."
    else
      unavailable = @guest_house_booking.errors.details[:base].any? { |detail| detail[:error] == :unavailable }
      only_availability_error = @guest_house_booking.errors.details.all? do |attribute, details|
        attribute == :base && details.all? { |detail| detail[:error] == :unavailable }
      end
      if unavailable && only_availability_error
        GuestHouseWaitlist.capture!(@guest_house_booking)
        @alternative_dates = @guest_house_booking.alternate_dates
        flash.now[:notice] = "No matching room is available right now. You have been added to the availability waitlist and will be notified if a suitable slot opens."
      end
      flash.now[:alert] = @guest_house_booking.errors.full_messages.to_sentence
      @single_room_eligible = @guest_house_booking.single_room_eligible?
      build_guest_detail_rows
      render :index, status: :unprocessable_entity
    end
  end

  def show
    @facilities_by_house = {
      @booking.guest_house_id => GuestHouseFacility.active
                                                  .where(guest_house_id: @booking.guest_house_id)
                                                  .ordered
    }
  end

  def destroy
    booking_reference = @booking.booking_reference_label
    @booking.destroy!
    redirect_to admin_guest_house_bookings_path, notice: "Booking #{booking_reference} deleted successfully."
  end

  def admin
    unless guest_house_admin?
      redirect_to guest_house_bookings_path, alert: "You are not authorized to access guest house admin bookings."
      return
    end

    @admin_bookings = GuestHouseBooking.includes(:guest_house, :guest_house_booking_guests, user: :employee_detail, accepted_by: :employee_detail)
                                      .for_admin(current_user)
                                      .recent_first
    @checkin_bookings = @admin_bookings.select { |booking| booking.confirmed? || booking.accepted? }
    @checkout_bookings = @admin_bookings.select(&:checked_in?)
    @payment_bookings = @admin_bookings.select do |booking|
      if booking.external_booking?
        booking.active_booking_guests.any?(&:billed?) && booking.active_booking_guests.any? { |guest| !guest.payment_complete? }
      else
        booking.checked_out? && !booking.payment_paid? && !booking.payment_waived?
      end
    end
    @closed_bookings = @admin_bookings.select do |booking|
      payment_complete = booking.external_booking? ? booking.active_booking_guests.present? && booking.active_booking_guests.all?(&:payment_complete?) : (booking.payment_paid? || booking.payment_waived?)
      booking.rejected? || booking.cancelled? || (booking.checked_out? && payment_complete)
    end
    @facilities_by_house = GuestHouseFacility.active
                                            .includes(:guest_house)
                                            .ordered
                                            .group_by(&:guest_house_id)
  end

  def accept
    if @booking.external_booking?
      redirect_to admin_guest_house_bookings_path, alert: "Accept each guest or auditor separately."
      return
    end

    accepted = false
    availability_message = nil
    @booking.guest_house.with_lock do
      @booking.reload
      if @booking.available_rooms_for_slot >= 0
        @booking.update!(status: "accepted", accepted_by: current_user, accepted_at: Time.current, admin_remark: admin_remark_param)
        accepted = true
      else
        availability_message = @booking.availability_error_message(include_alternates: true)
      end
    end

    unless accepted
      redirect_to admin_guest_house_bookings_path, alert: availability_message
      return
    end

    redirect_to admin_guest_house_bookings_path, notice: "Booking accepted successfully."
  end

  def reject
    if @booking.external_booking?
      redirect_to admin_guest_house_bookings_path, alert: "Reject each guest or auditor separately."
      return
    end

    remark = admin_remark_param.presence || params.dig(:guest_house_booking, :rejection_remark).to_s
    if remark.blank?
      redirect_to admin_guest_house_bookings_path, alert: "Reject remark is required."
      return
    end

    @booking.update!(status: "rejected", accepted_by: current_user, admin_remark: remark, rejection_remark: remark)
    GuestHouseNotificationService.booking_rejected(@booking)
    GuestHouseWaitlist.notify_available_for!(@booking, actor: current_user)
    redirect_to admin_guest_house_bookings_path, notice: "Booking rejected."
  end

  def cancel
    unless @booking.cancellable?
      redirect_to guest_house_booking_path(@booking), alert: "Cancellation is available only before any occupant checks in."
      return
    end

    reason = cancellation_params[:cancellation_reason].to_s.strip
    if reason.blank?
      redirect_to guest_house_booking_path(@booking), alert: "Cancellation reason is required."
      return
    end

    @booking.update!(
      status: "cancelled",
      cancellation_reason: reason,
      cancelled_at: Time.current,
      cancelled_by: current_user
    )
    GuestHouseNotificationService.booking_cancelled(@booking, actor: current_user)
    GuestHouseWaitlist.notify_available_for!(@booking, actor: current_user)

    destination = guest_house_admin_for?(@booking.guest_house) ? admin_guest_house_bookings_path : guest_house_bookings_path
    redirect_to destination, notice: "Booking #{@booking.booking_reference_label} cancelled successfully."
  end

  def check_in
    if @booking.external_booking?
      redirect_to admin_guest_house_bookings_path, alert: "Use individual occupant check-in for Guest and Auditor bookings."
      return
    end

    @booking.id_proof.attach(check_in_params[:id_proof]) if check_in_params[:id_proof].present?
    @booking.update!(check_in_params.except(:id_proof).merge(status: "checked_in", checked_in_at: Time.current))
    redirect_to admin_guest_house_bookings_path, notice: "Check-in started successfully."
  end

  def checkout
    if checkout_params[:extended_checkout_date].present? || checkout_params[:extended_checkout_time].present?
      updated = @booking.guest_house.with_lock do
        @booking.reload
        @booking.update(checkout_params.merge(status: "checked_in"))
      end

      if updated
        GuestHouseNotificationService.checkout_extended(@booking, actor: current_user)
        redirect_to admin_guest_house_bookings_path, notice: "Checkout time extended successfully."
      else
        redirect_to admin_guest_house_bookings_path, alert: @booking.errors.full_messages.to_sentence
      end
    else
      if @booking.external_booking? && !@booking.all_occupants_checked_out?
        redirect_to admin_guest_house_bookings_path, alert: "Complete checkout for every guest or auditor before generating the final bill."
        return
      end

      billing_params = checkout_billing_params
      @booking.assign_attributes(billing_params)
      apply_selected_facility_charge
      @booking.status = "checked_out"
      @booking.checked_out_at = Time.current
      override_room_charge = params[:override_room_charge] == "1"
      @booking.room_charge_overridden = override_room_charge
      room_charge_override = override_room_charge ? billing_params[:room_charge_amount] : nil
      calculated_room_charge = room_charge_override.nil? ? @booking.room_charge_total(as_of: @booking.checked_out_at) : room_charge_override
      @booking.calculate_bill!(room_charge_amount: calculated_room_charge)
      @booking.save!
      GuestHouseNotificationService.checkout_completed(@booking, actor: current_user)
      redirect_to guest_house_booking_path(@booking), notice: "Checkout completed and bill generated successfully."
    end
  end

  def submit_complaint
    if @booking.user_id != current_user.id
      redirect_to guest_house_booking_path(@booking), alert: "Only guest can submit complaint."
      return
    end

    @booking.update!(
      guest_complaint: complaint_params[:guest_complaint],
      complaint_submitted_at: Time.current,
      complaint_status: "open"
    )
    GuestHouseNotificationService.complaint_submitted(@booking, actor: current_user)
    redirect_to guest_house_booking_path(@booking), notice: "Complaint submitted successfully."
  end

  def submit_feedback
    if @booking.user_id != current_user.id
      redirect_to guest_house_booking_path(@booking), alert: "Only the booking owner can submit feedback."
      return
    end

    unless @booking.checked_out?
      redirect_to guest_house_booking_path(@booking), alert: "Feedback is available after checkout."
      return
    end

    unless feedback_params[:feedback_rating].to_i.in?(1..5)
      redirect_to guest_house_booking_path(@booking), alert: "Please select a feedback rating from 1 to 5."
      return
    end

    if @booking.update(feedback_params.merge(feedback_submitted_at: Time.current))
      GuestHouseNotificationService.feedback_submitted(@booking, actor: current_user)
      redirect_to guest_house_booking_path(@booking), notice: "Feedback saved successfully."
    else
      redirect_to guest_house_booking_path(@booking), alert: @booking.errors.full_messages.to_sentence
    end
  end

  def generate_payment
    @booking.assign_attributes(payment_params)
    apply_selected_facility_charge
    @booking.room_charge_overridden = payment_params[:room_charge_amount].present?
    @booking.calculate_bill!(room_charge_amount: payment_params[:room_charge_amount])
    @booking.update!(
      bill_amount: @booking.total_bill_amount,
      payment_note: payment_params[:payment_note],
      payment_status: "generated"
    )
    GuestHouseNotificationService.payment_generated(@booking, actor: current_user)
    redirect_to guest_house_booking_path(@booking), notice: "Payment QR generated successfully."
  end

  def upload_payment
    if @booking.invoice_total.to_d <= 0 && !@booking.room_charge_overridden?
      @booking.calculate_bill!(room_charge_amount: @booking.room_charge_total(as_of: @booking.checked_out_at || Time.current))
    end
    @booking.payment_receipt.attach(payment_upload_params[:payment_receipt]) if payment_upload_params[:payment_receipt].present?
    @booking.payment_qr_image.attach(payment_upload_params[:payment_qr_image]) if payment_upload_params[:payment_qr_image].present?
    status = payment_upload_params[:payment_status].presence || "paid"
    @booking.payment_status = status
    @booking.transaction_id = payment_upload_params[:transaction_id]
    @booking.payment_details = payment_upload_params[:payment_details]
    if %w[paid waived].include?(status)
      @booking.paid_at ||= Time.current
      @booking.ensure_payment_receipt_number!
    end
    @booking.save!
    GuestHouseNotificationService.payment_updated(@booking, actor: current_user)
    redirect_to guest_house_booking_path(@booking), notice: "Payment status updated successfully."
  end

  def receipt
    unless @booking.self_booking? && (@booking.payment_paid? || @booking.payment_waived?)
      redirect_to guest_house_booking_path(@booking), alert: "Payment receipt is available after payment completion."
      return
    end

    @receipt_booking = @booking
    @receipt_guest = nil
    render_guest_house_receipt
  end

  private

  def render_guest_house_receipt
    disposition = params[:download] == "1" ? "attachment" : "inline"
    filename = "Guest_House_Receipt_#{@receipt_booking.payment_receipt_number || @receipt_booking.booking_reference_label}"
    render pdf: filename,
           template: "guest_house_receipts/receipt",
           formats: [ :pdf ],
           layout: "pdf",
           page_size: "A4",
           margin: { top: 8, bottom: 8, left: 8, right: 8 },
           disposition: disposition,
           print_media_type: true
  end

  def load_guest_house_context
    @guest_houses = GuestHouse.active.ordered
    @admin_booking_count = guest_house_admin? ? GuestHouseBooking.for_admin(current_user).where(status: %w[confirmed accepted checked_in]).count : 0
  end

  def set_booking
    @booking = GuestHouseBooking.includes(:guest_house, :guest_house_booking_guests, user: :employee_detail, accepted_by: :employee_detail).find(params[:id])
  end

  def ensure_booking_owner_or_admin!
    return if @booking.user_id == current_user.id || guest_house_admin_for?(@booking.guest_house)

    redirect_to guest_house_bookings_path, alert: "You are not authorized to view this booking."
  end

  def ensure_guest_house_admin!
    return if guest_house_admin_for?(@booking.guest_house)

    redirect_to guest_house_bookings_path, alert: "You are not authorized to manage this booking."
  end

  def ensure_hod!
    return if current_user&.hod?

    redirect_to guest_house_bookings_path, alert: "Only HOD can delete guest house bookings."
  end

  def ensure_confirmed!
    return if @booking.confirmed?

    redirect_to admin_guest_house_bookings_path, alert: "Only confirmed bookings can be accepted."
  end

  def ensure_rejectable!
    return if @booking.confirmed? || @booking.accepted?

    redirect_to admin_guest_house_bookings_path, alert: "Only pending check-in bookings can be rejected."
  end

  def ensure_accepted!
    return if @booking.accepted?

    redirect_to admin_guest_house_bookings_path, alert: "Check-in is available only after booking acceptance."
  end

  def ensure_checked_in!
    return if @booking.checked_in?

    redirect_to admin_guest_house_bookings_path, alert: "Checkout is available only after guest check-in."
  end

  def ensure_checked_out!
    return if @booking.checked_out?

    redirect_to admin_guest_house_bookings_path, alert: "Payment update is available only after checkout bill."
  end

  def guest_house_admin?
    current_user.hod? || current_user.managed_guest_houses.exists?
  end

  def guest_house_admin_for?(guest_house)
    current_user.hod? || guest_house.manager_user_id == current_user.id
  end

  def booking_params
    params.require(:guest_house_booking).permit(
      :guest_house_id, :booking_date, :checkin_time, :checkout_date, :checkout_time, :rooms_count,
      :room_type, :guest_gender, :booking_for,
      guest_house_booking_guests_attributes: [
        :id, :first_name, :last_name, :aadhaar_number, :mobile_number, :email, :gender, :age,
        :organization, :designation, :purpose, :checkin_date, :checkin_time, :checkout_date, :checkout_time, :_destroy
      ]
    )
  end

  def admin_remark_param
    params.fetch(:guest_house_booking, {}).fetch(:admin_remark, "")
  end

  def check_in_params
    params.require(:guest_house_booking).permit(:id_proof_type, :id_proof_number, :id_proof, :checkin_remark)
  end

  def checkout_params
    params.fetch(:guest_house_booking, {}).permit(:extended_checkout_date, :extended_checkout_time)
  end

  def checkout_billing_params
    params.fetch(:guest_house_booking, {}).permit(:room_charge_amount, :other_services_amount, :other_services_details, :payment_note)
  end

  def selected_facility_params
    params.fetch(:guest_house_booking, {}).permit(facility_ids: [], facility_quantities: {})
  end

  def apply_selected_facility_charge
    facility_ids = Array(selected_facility_params[:facility_ids]).reject(&:blank?)
    return if facility_ids.blank?

    quantities = selected_facility_params[:facility_quantities] || {}
    facilities = GuestHouseFacility.active
                                   .where(id: facility_ids, guest_house_id: @booking.guest_house_id)
                                   .index_by { |facility| facility.id.to_s }
    selected_lines = facility_ids.filter_map do |facility_id|
      facility = facilities[facility_id.to_s]
      next if facility.blank?

      quantity = quantities[facility_id.to_s].to_i
      quantity = 1 if quantity <= 0
      selected_amount = facility.rate.to_d * quantity
      "#{facility.name} x #{quantity} @ Rs. #{format('%.2f', facility.rate)} = Rs. #{format('%.2f', selected_amount)}"
    end

    selected_amount = facility_ids.sum do |facility_id|
      facility = facilities[facility_id.to_s]
      next 0.to_d if facility.blank?

      quantity = quantities[facility_id.to_s].to_i
      quantity = 1 if quantity <= 0
      facility.rate.to_d * quantity
    end
    return if selected_amount.zero?

    current_amount = @booking.other_services_amount.to_d
    current_details = @booking.other_services_details.to_s.strip

    @booking.other_services_amount = current_amount + selected_amount
    @booking.other_services_details = [ current_details.presence, selected_lines.join("\n").presence ].compact.join("\n")
  end

  def complaint_params
    params.require(:guest_house_booking).permit(:guest_complaint)
  end

  def cancellation_params
    params.fetch(:guest_house_booking, {}).permit(:cancellation_reason)
  end

  def feedback_params
    params.require(:guest_house_booking).permit(:feedback_rating, :feedback_comment)
  end

  def payment_params
    params.require(:guest_house_booking).permit(:room_charge_amount, :other_services_amount, :other_services_details, :payment_note)
  end

  def payment_upload_params
    params.require(:guest_house_booking).permit(:payment_status, :payment_receipt, :payment_qr_image, :transaction_id, :payment_details)
  end

  def build_guest_detail_rows
    rows_required = [ @guest_house_booking.rooms_count.to_i, 1 ].max
    rows_required = 1 if @guest_house_booking.self_booking?
    rows_to_build = rows_required - @guest_house_booking.guest_house_booking_guests.size
    rows_to_build.times { @guest_house_booking.guest_house_booking_guests.build } if rows_to_build.positive?
  end
end
