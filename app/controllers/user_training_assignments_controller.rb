class UserTrainingAssignmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_hod!

  # GET /user_training_assignments
  # Shows list of ALL 42 employees with completion summary
  def index
    @employees = EmployeeDetail.includes(:user, :user_training_assignments, user: :user_training_progresses)
                               .order(:employee_name)
  end

  def export_xlsx
    @employees = EmployeeDetail.includes(:user, user_training_assignments: :training, user: { user_training_progresses: :training }).order(:employee_name)
    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=Employee_Training_Data_#{Date.today}.xlsx"
      }
    end
  end

  # GET /user_training_assignments/:employee_detail_id
  # Shows detailed progress for a specific employee
  def show
    @employee = EmployeeDetail.includes(:user, user: { user_training_progresses: :training }).find(params[:employee_detail_id])
    @assigned_trainings = @employee.assigned_trainings.includes(:user_training_progresses)

    # Map progress for easy access
    @progress_map = {}
    if @employee.user
      @employee.user.user_training_progresses.each do |p|
        @progress_map[p.training_id] = p
      end
    end
  end


  # GET /user_training_assignments/:employee_detail_id/edit
  # Shows all trainings grouped by month for a specific employee with checkboxes
  def edit
    @employee = EmployeeDetail.includes(:user).find(params[:employee_detail_id])
    all_trainings = Training.order(:year, :month, :title)
    @trainings_by_month = all_trainings.group_by { |t| [ t.year, t.month ] }

    if @employee.assignments_managed?
      # HOD has explicitly managed this employee → show only their assigned training IDs
      @assigned_ids = @employee.user_training_assignments.pluck(:training_id)
    else
      # Unmanaged employee → pre-tick ALL trainings (they currently see everything by default)
      @assigned_ids = all_trainings.pluck(:id)
    end
  end

  # PATCH /user_training_assignments/:employee_detail_id
  # Updates assignments for a specific employee
  def update
    @employee = EmployeeDetail.find(params[:employee_detail_id])
    selected_ids = (params[:training_ids] || []).map(&:to_i)

    # Remove all existing assignments for this employee
    @employee.user_training_assignments.destroy_all

    # Create new assignments for selected trainings
    selected_ids.each do |training_id|
      @employee.user_training_assignments.create(
        training_id: training_id,
        user_id: @employee.user_id   # link user_id if they have a login
      )
    end

    # ✅ Mark this employee as HOD-managed so new trainings won't auto-appear
    @employee.update_column(:assignments_managed, true)

    redirect_to user_training_assignments_path,
                notice: "Training assignments updated for #{@employee.employee_name}"
  end

  private

  def require_hod!
    unless current_user.hod?
      redirect_to root_path, alert: "Access denied."
    end
  end
end
