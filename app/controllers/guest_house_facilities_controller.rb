class GuestHouseFacilitiesController < ApplicationController
  before_action :ensure_hod!
  before_action :set_facility, only: [ :update, :destroy ]

  def create
    facility = GuestHouseFacility.new(facility_params)

    if facility.save
      redirect_to guest_houses_path, notice: "Facility added successfully."
    else
      redirect_to guest_houses_path, alert: facility.errors.full_messages.to_sentence
    end
  end

  def update
    if @facility.update(facility_params)
      redirect_to guest_houses_path, notice: "Facility updated successfully."
    else
      redirect_to guest_houses_path, alert: @facility.errors.full_messages.to_sentence
    end
  end

  def destroy
    @facility.destroy
    redirect_to guest_houses_path, notice: "Facility deleted successfully."
  end

  private

  def ensure_hod!
    redirect_to guest_house_bookings_path, alert: "You are not authorized to manage guest house facilities." unless current_user.hod?
  end

  def set_facility
    @facility = GuestHouseFacility.find(params[:id])
  end

  def facility_params
    params.require(:guest_house_facility).permit(:guest_house_id, :name, :rate, :active)
  end
end
