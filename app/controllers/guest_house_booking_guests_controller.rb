class GuestHouseBookingGuestsController < ApplicationController
  before_action :set_guest
  before_action :ensure_guest_house_admin!, except: [ :bill, :receipt ]

  def bill
    unless @guest.billed? && (current_user.id == @booking.user_id || guest_house_admin?)
      redirect_to guest_house_bookings_path, alert: "You are not authorized to view this bill."
    end
  end

  def receipt
    unless @guest.payment_complete? && (current_user.id == @booking.user_id || guest_house_admin?)
      redirect_to guest_house_bookings_path, alert: "Payment receipt is available after payment completion."
      return
    end

    @receipt_booking = @booking
    @receipt_guest = @guest
    disposition = params[:download] == "1" ? "attachment" : "inline"
    filename = "Guest_House_Receipt_#{@guest.payment_receipt_number || @booking.booking_reference_label}"
    render pdf: filename,
           template: "guest_house_receipts/receipt",
           formats: [ :pdf ],
           layout: "pdf",
           page_size: "A4",
           margin: { top: 8, bottom: 8, left: 8, right: 8 },
           disposition: disposition,
           print_media_type: true
  end

  def accept
    unless @guest.approval_pending? && @booking.external_booking?
      redirect_to admin_guest_house_bookings_path, alert: "This occupant is not awaiting approval."
      return
    end

    remark = approval_params[:approval_remark].to_s.strip
    if remark.blank?
      redirect_to admin_guest_house_bookings_path, alert: "Remark is required for #{@guest.full_name}."
      return
    end

    @guest.update!(
      approval_status: "accepted",
      accepted_by: current_user,
      accepted_at: Time.current,
      approval_remark: remark,
      rejection_remark: nil
    )
    sync_booking_approval!
    GuestHouseNotificationService.occupant_accepted(@guest, actor: current_user)
    redirect_to admin_guest_house_bookings_path, notice: "#{@guest.full_name} accepted successfully."
  end

  def reject
    unless @guest.approval_pending? && @booking.external_booking?
      redirect_to admin_guest_house_bookings_path, alert: "This occupant is not awaiting approval."
      return
    end

    remark = approval_params[:approval_remark].to_s.strip
    if remark.blank?
      redirect_to admin_guest_house_bookings_path, alert: "Remark is required for #{@guest.full_name}."
      return
    end

    @guest.update!(
      approval_status: "rejected",
      approval_remark: remark,
      rejection_remark: remark,
      accepted_by: current_user,
      accepted_at: Time.current
    )
    sync_booking_approval!
    GuestHouseNotificationService.occupant_rejected(@guest, actor: current_user)
    GuestHouseWaitlist.notify_available_for!(@booking, actor: current_user)
    redirect_to admin_guest_house_bookings_path, notice: "#{@guest.full_name} rejected."
  end

  def check_in
    unless @guest.approval_accepted? && @guest.stay_pending? && (@booking.confirmed? || @booking.accepted? || @booking.checked_in?)
      redirect_to admin_guest_house_bookings_path, alert: "This occupant is not ready for check-in."
      return
    end

    if @guest.planned_checkin_at.present? && Time.current < @guest.planned_checkin_at
      redirect_to admin_guest_house_bookings_path, alert: "#{@guest.full_name} is scheduled for check-in at #{@guest.planned_checkin_at.strftime('%d %b %Y, %I:%M %p')}."
      return
    end

    @guest.id_proof.attach(check_in_params[:id_proof]) if check_in_params[:id_proof].present?
    @guest.update!(
      check_in_params.except(:id_proof).merge(
        stay_status: "checked_in",
        checked_in_at: Time.current
      )
    )
    @booking.update!(status: "checked_in", checked_in_at: @booking.checked_in_at || Time.current)
    GuestHouseNotificationService.occupant_checked_in(@guest, actor: current_user)
    redirect_to admin_guest_house_bookings_path, notice: "#{@guest.full_name} checked in successfully."
  end

  def check_out
    unless @guest.stay_checked_in?
      redirect_to admin_guest_house_bookings_path, alert: "Only a checked-in occupant can be checked out."
      return
    end

    @guest.update!(
      stay_status: "checked_out",
      checked_out_at: Time.current,
      checkout_remark: check_out_params[:checkout_remark]
    )
    GuestHouseNotificationService.occupant_checked_out(@guest, actor: current_user)
    redirect_to admin_guest_house_bookings_path, notice: "#{@guest.full_name} checked out successfully."
  end

  def generate_bill
    unless @guest.stay_checked_out?
      redirect_to admin_guest_house_bookings_path, alert: "Complete #{@guest.full_name}'s checkout before generating the bill."
      return
    end

    previous_total = @guest.total_bill_amount.to_d if @guest.billed?
    billing = bill_params
    @guest.assign_attributes(billing)
    apply_selected_facility_charge
    override_room_charge = params[:override_room_charge] == "1"
    @guest.room_charge_overridden = override_room_charge
    room_charge_override = override_room_charge ? billing[:room_charge_amount] : nil
    @guest.calculate_bill!(room_charge_amount: room_charge_override)
    if previous_total.present? && previous_total != @guest.total_bill_amount.to_d
      @guest.payment_status = "generated"
      @guest.paid_at = nil
    end
    @guest.save!
    sync_booking_bill!

    redirect_path = params[:return_to_bill] == "1" ? bill_guest_house_booking_guest_path(@guest) : admin_guest_house_bookings_path
    redirect_to redirect_path, notice: "Individual bill saved for #{@guest.full_name}."
  end

  def upload_payment
    unless @guest.billed?
      redirect_to admin_guest_house_bookings_path, alert: "Generate #{@guest.full_name}'s bill before payment."
      return
    end

    @guest.payment_receipt.attach(payment_params[:payment_receipt]) if payment_params[:payment_receipt].present?
    @guest.payment_qr_image.attach(payment_params[:payment_qr_image]) if payment_params[:payment_qr_image].present?
    status = payment_params[:payment_status].presence || "paid"
    @guest.payment_status = status
    @guest.transaction_id = payment_params[:transaction_id]
    @guest.payment_details = payment_params[:payment_details]
    if %w[paid waived].include?(status)
      @guest.paid_at ||= Time.current
      @guest.ensure_payment_receipt_number!
    else
      @guest.paid_at = nil
    end
    @guest.save!
    sync_booking_bill!
    GuestHouseNotificationService.occupant_payment_updated(@guest, actor: current_user)

    redirect_to bill_guest_house_booking_guest_path(@guest), notice: "Payment updated for #{@guest.full_name}."
  end

  private

  def set_guest
    @guest = GuestHouseBookingGuest.includes(guest_house_booking: :guest_house).find(params[:id])
    @booking = @guest.guest_house_booking
  end

  def ensure_guest_house_admin!
    return if guest_house_admin?

    redirect_to guest_house_bookings_path, alert: "You are not authorized to manage this occupant."
  end

  def guest_house_admin?
    current_user.hod? || @booking.guest_house.manager_user_id == current_user.id
  end

  def check_in_params
    params.require(:guest_house_booking_guest).permit(:id_proof_type, :id_proof_number, :id_proof, :checkin_remark)
  end

  def check_out_params
    params.fetch(:guest_house_booking_guest, {}).permit(:checkout_remark)
  end

  def approval_params
    params.fetch(:guest_house_booking_guest, {}).permit(:approval_remark, :rejection_remark)
  end

  def bill_params
    params.fetch(:guest_house_booking_guest, {}).permit(:room_charge_amount, :other_services_amount, :other_services_details, :bill_note)
  end

  def selected_facility_params
    params.fetch(:guest_house_booking_guest, {}).permit(facility_ids: [], facility_quantities: {})
  end

  def payment_params
    params.require(:guest_house_booking_guest).permit(:payment_status, :payment_receipt, :payment_qr_image, :transaction_id, :payment_details)
  end

  def apply_selected_facility_charge
    facility_ids = Array(selected_facility_params[:facility_ids]).reject(&:blank?)
    return if facility_ids.blank?

    quantities = selected_facility_params[:facility_quantities] || {}
    facilities = GuestHouseFacility.active.where(id: facility_ids, guest_house_id: @booking.guest_house_id).index_by { |facility| facility.id.to_s }
    lines = facility_ids.filter_map do |facility_id|
      facility = facilities[facility_id.to_s]
      next if facility.blank?

      quantity = [ quantities[facility_id.to_s].to_i, 1 ].max
      amount = facility.rate.to_d * quantity
      "#{facility.name} x #{quantity} @ Rs. #{format('%.2f', facility.rate)} = Rs. #{format('%.2f', amount)}"
    end

    facility_total = facility_ids.sum do |facility_id|
      facility = facilities[facility_id.to_s]
      next 0.to_d if facility.blank?

      facility.rate.to_d * [ quantities[facility_id.to_s].to_i, 1 ].max
    end
    manual_amount = @guest.other_services_amount.to_d
    manual_details = @guest.other_services_details.to_s.strip
    @guest.other_services_amount = manual_amount + facility_total
    @guest.other_services_details = ([ manual_details.presence ] + lines).compact.join("\n")
  end

  def sync_booking_bill!
    guests = @booking.guest_house_booking_guests.reload.select(&:active_occupant?)
    billed_guests = guests.select(&:billed?)
    @booking.room_charge_amount = billed_guests.sum(&:room_charge_amount)
    @booking.room_charge_overridden = billed_guests.any?(&:room_charge_overridden?)
    @booking.other_services_amount = billed_guests.sum(&:other_services_amount)
    @booking.gst_amount = billed_guests.sum(&:gst_amount)
    @booking.total_bill_amount = billed_guests.sum(&:total_bill_amount)
    @booking.bill_amount = @booking.total_bill_amount

    if guests.all?(&:stay_checked_out?) && guests.all?(&:billed?)
      @booking.status = "checked_out"
      @booking.checked_out_at ||= guests.filter_map(&:checked_out_at).max || Time.current
      @booking.payment_status = if guests.all?(&:payment_complete?)
                                  guests.all?(&:payment_waived?) ? "waived" : "paid"
                                elsif guests.any?(&:payment_uploaded?)
                                  "uploaded"
                                else
                                  "generated"
                                end
    end
    @booking.save!
  end

  def sync_booking_approval!
    guests = @booking.guest_house_booking_guests.reload
    active_guests = guests.select(&:active_occupant?)
    @booking.status = if active_guests.empty?
                        "rejected"
                      elsif active_guests.any?(&:stay_checked_in?)
                        "checked_in"
                      elsif guests.any?(&:approval_pending?)
                        "confirmed"
                      else
                        "accepted"
                      end
    @booking.accepted_by = current_user if active_guests.any?(&:approval_accepted?)
    @booking.accepted_at ||= Time.current if active_guests.any?(&:approval_accepted?)
    @booking.save!
  end
end
