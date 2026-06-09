class EmployeeTrainingThematicsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hod!

  def index
    @employee_training_thematic = EmployeeTrainingThematic.new
    @employee_training_thematics = EmployeeTrainingThematic.ordered
  end

  def create
    @employee_training_thematic = EmployeeTrainingThematic.new(employee_training_thematic_attributes)
    @employee_training_thematic.created_by = current_user

    if @employee_training_thematic.save
      redirect_to employee_training_thematics_path, notice: "Thematic/Department created successfully."
    else
      @employee_training_thematics = EmployeeTrainingThematic.ordered
      flash.now[:alert] = @employee_training_thematic.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    EmployeeTrainingThematic.find(params[:id]).destroy
    redirect_to employee_training_thematics_path, notice: "Thematic/Department deleted successfully."
  end

  private

  def ensure_hod!
    redirect_to trainings_path, alert: "You are not authorized to manage thematic departments." unless current_user.hod?
  end

  def employee_training_thematic_params
    params.require(:employee_training_thematic).permit(:thematic_department_name, :active)
  end

  def employee_training_thematic_attributes
    thematic_department_name = employee_training_thematic_params[:thematic_department_name].to_s.strip

    {
      thematic_type: thematic_department_name,
      department_name: thematic_department_name,
      active: employee_training_thematic_params.fetch(:active, true)
    }
  end
end
