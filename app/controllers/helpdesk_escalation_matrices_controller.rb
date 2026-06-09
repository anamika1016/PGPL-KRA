class HelpdeskEscalationMatricesController < ApplicationController
  before_action :set_helpdesk_escalation_matrix, only: [ :edit, :update, :destroy ]
  before_action :ensure_hod!
  before_action :load_helpdesk_escalation_support_data, only: [ :index, :create, :edit, :update ]

  def index
    @helpdesk_escalation_matrix = HelpdeskEscalationMatrix.new
    @helpdesk_escalation_matrix.build_default_escalations
  end

  def create
    @helpdesk_escalation_matrix = HelpdeskEscalationMatrix.new(helpdesk_escalation_matrix_params)

    if @helpdesk_escalation_matrix.save
      redirect_to helpdesk_escalation_matrices_path, notice: "Helpdesk escalation matrix created successfully."
    else
      @helpdesk_escalation_matrix.build_default_escalations(1)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @helpdesk_escalation_matrix.build_default_escalations(1)
    render :index
  end

  def update
    if @helpdesk_escalation_matrix.update(helpdesk_escalation_matrix_params)
      redirect_to helpdesk_escalation_matrices_path, notice: "Helpdesk escalation matrix updated successfully."
    else
      @helpdesk_escalation_matrix.build_default_escalations(1)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @helpdesk_escalation_matrix.destroy
    redirect_to helpdesk_escalation_matrices_path, notice: "Helpdesk escalation matrix deleted successfully."
  end

  private

  def set_helpdesk_escalation_matrix
    @helpdesk_escalation_matrix = HelpdeskEscalationMatrix.find(params[:id])
  end

  def load_helpdesk_escalation_support_data
    @departments = helpdesk_selectable_departments
    @manager_options = build_manager_options
    @helpdesk_escalation_matrices = HelpdeskEscalationMatrix.includes(:department, escalation_levels: :user)
                                                            .ordered_by_department
  end

  def helpdesk_escalation_matrix_params
    permitted_params = params.require(:helpdesk_escalation_matrix).permit(
      :department_id,
      escalation_levels_attributes: [ :id, :position, :user_id, :_destroy ]
    )

    trim_escalation_levels_to_l2(permitted_params)
    permitted_params
  end

  def trim_escalation_levels_to_l2(permitted_params)
    level_attributes = permitted_params[:escalation_levels_attributes]
    return if level_attributes.blank?

    active_index = 0

    level_attributes.each_value do |attributes|
      next if ActiveModel::Type::Boolean.new.cast(attributes[:_destroy])

      active_index += 1
      if active_index > HelpdeskEscalationMatrix::MAX_ESCALATION_LEVELS
        attributes[:_destroy] = "1"
        attributes[:user_id] = nil
      end
    end
  end

  def build_manager_options
    helpdesk_employee_option_users.map do |user|
      employee_detail = user.mapped_employee_detail

      display_name = employee_detail&.employee_name.presence || user.display_name
      identifier = employee_detail&.employee_code.presence || user.employee_code.presence || "Not available"

      [ "#{display_name} (#{identifier})", user.id ]
    end.sort_by(&:first)
  end

  def ensure_hod!
    return if current_user&.hod?

    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
