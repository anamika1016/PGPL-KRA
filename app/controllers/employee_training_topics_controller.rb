class EmployeeTrainingTopicsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hod!
  before_action :load_form_options, only: [ :index, :create ]

  def index
    @employee_training_topic = EmployeeTrainingTopic.new
    @employee_training_topics = EmployeeTrainingTopic.ordered
  end

  def create
    @employee_training_topic = EmployeeTrainingTopic.new(employee_training_topic_params)
    @employee_training_topic.created_by = current_user

    if @employee_training_topic.save
      redirect_to employee_training_topics_path, notice: "Training topic created successfully."
    else
      @employee_training_topics = EmployeeTrainingTopic.ordered
      flash.now[:alert] = @employee_training_topic.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    EmployeeTrainingTopic.find(params[:id]).destroy
    redirect_to employee_training_topics_path, notice: "Training topic deleted successfully."
  end

  private

  def ensure_hod!
    redirect_to trainings_path, alert: "You are not authorized to manage training topics." unless current_user.hod?
  end

  def load_form_options
    @thematic_department_options = EmployeeTrainingThematic.active.ordered.map(&:display_name)
  end

  def employee_training_topic_params
    params.require(:employee_training_topic).permit(:thematic_department_name, :name, :active)
  end
end
