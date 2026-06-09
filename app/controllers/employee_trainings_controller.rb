class EmployeeTrainingsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_form_options, only: [ :new, :create ]
  before_action :set_employee_training, only: [ :show ]

  def index
    @employee_trainings = EmployeeTraining
      .includes(training_register_attachment: :blob, photo_upload_attachment: :blob)
      .recent_first
  end

  def new
    @employee_training = EmployeeTraining.new
  end

  def show
    @selected_employees = @employee_training.selected_employees
  end

  def create
    @employee_training = current_user.employee_trainings.new(employee_training_attributes)

    if @employee_training.save
      redirect_to @employee_training, notice: "Employee training details saved successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_employee_training
    @employee_training = EmployeeTraining.find(params[:id])
  end

  def employee_training_attributes
    {
      office_types: Array(params[:office_type]),
      office_names: Array(params[:office_name]),
      thematic_department_name: params[:thematic_department_name],
      training_date: params[:training_date],
      topic: params[:topic],
      other_topic: params[:other_topic],
      details: params[:details],
      training_location: params[:training_location],
      asa_participants: params[:asa_participants],
      other_participants: params[:other_participants],
      qr_id: params[:qr_id],
      employee_detail_ids: Array(params[:employee_ids]),
      training_register: params[:training_register],
      photo_upload: params[:photo_upload]
    }
  end

  def load_form_options
    office_rows = EmployeeDetail
      .where.not(office_type: [ nil, "" ], office_name: [ nil, "" ])
      .distinct
      .order(:office_type, :office_name)
      .pluck(:office_type, :office_name)

    @office_options_by_type = office_rows.each_with_object({}) do |(office_type, office_name), grouped|
      office_type = office_type.to_s.strip
      office_name = office_name.to_s.strip
      next if office_type.blank? || office_name.blank?

      grouped[office_type] ||= []
      grouped[office_type] << office_name unless grouped[office_type].include?(office_name)
    end

    @office_type_options = @office_options_by_type.keys.sort
    @office_options = @office_options_by_type.values.flatten.uniq.sort

    @thematic_department_options = EmployeeTrainingThematic.active.ordered.map(&:display_name)

    @topics_by_thematic_department = EmployeeTrainingTopic
      .active
      .ordered
      .pluck(:thematic_department_name, :name)
      .each_with_object({}) do |(thematic_department_name, topic_name), grouped|
        thematic_department_name = thematic_department_name.to_s.strip
        topic_name = topic_name.to_s.strip
        next if thematic_department_name.blank? || topic_name.blank?

        grouped[thematic_department_name] ||= []
        grouped[thematic_department_name] << topic_name unless grouped[thematic_department_name].include?(topic_name)
      end

    @employees = EmployeeDetail
      .where.not(employee_code: [ nil, "" ])
      .order(:employee_code)
      .select(:id, :employee_code, :employee_name)
  end
end
