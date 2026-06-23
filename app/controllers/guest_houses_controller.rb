class GuestHousesController < ApplicationController
  before_action :ensure_hod!
  before_action :set_guest_house, only: [ :show, :update, :destroy ]

  def index
    @guest_house = GuestHouse.new
    @guest_houses = GuestHouse.includes(manager_user: :employee_detail).ordered
    @guest_house_facility = GuestHouseFacility.new
    @guest_house_facilities = GuestHouseFacility.includes(:guest_house).ordered
    @manager_options = User.includes(:employee_detail).order(:email).map { |user| [ user.display_name, user.id ] }
  end

  def create
    @guest_house = GuestHouse.new(guest_house_params)
    @guest_house.created_by = current_user

    if @guest_house.save
      redirect_to guest_houses_path, notice: "Guest house added successfully."
    else
      load_index_context
      flash.now[:alert] = @guest_house.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def show
    redirect_to guest_houses_path
  end

  def update
    updated = @guest_house.with_lock do
      @guest_house.reload
      @guest_house.update(guest_house_params)
    end

    if updated
      redirect_to guest_houses_path, notice: "Guest house updated successfully."
    else
      load_index_context
      flash.now[:alert] = @guest_house.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    if @guest_house.destroy
      redirect_to guest_houses_path, notice: "Guest house deleted successfully."
    else
      redirect_to guest_houses_path, alert: @guest_house.errors.full_messages.to_sentence
    end
  end

  private

  def ensure_hod!
    redirect_to guest_house_bookings_path, alert: "You are not authorized to manage guest house master." unless current_user.hod?
  end

  def set_guest_house
    @guest_house = GuestHouse.find(params[:id])
  end

  def load_index_context
    @guest_houses = GuestHouse.includes(manager_user: :employee_detail).ordered
    @guest_house_facility = GuestHouseFacility.new
    @guest_house_facilities = GuestHouseFacility.includes(:guest_house).ordered
    @manager_options = User.includes(:employee_detail).order(:email).map { |user| [ user.display_name, user.id ] }
  end

  def guest_house_params
    params.require(:guest_house).permit(:name, :total_rooms, :manager_user_id, :room_charge_per_day, :active)
  end
end
