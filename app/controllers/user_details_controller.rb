class UserDetailsController < ApplicationController
  require "ostruct"
  require "set"
  before_action :set_user_detail, only: [ :show, :edit, :update, :destroy ]
  load_and_authorize_resource except: [ :index, :new, :create, :get_user_detail, :get_activities, :bulk_create, :submit_achievements, :export, :import, :quarterly_edit_all, :update_quarterly_achievements, :test_sms, :view_sms_logs, :submitted_achievements, :export_department_activity_data, :clear_sms_tracking ]

  def index
    if current_user.role == "employee" || current_user.role == "l1_employer" || current_user.role == "l2_employer"
      employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail)
                               .assignment_consistent
                               .for_financial_year(selected_financial_year)
                               .where(employee_detail_id: employee_detail.id)

        # Deduplicate by keeping the most recent record for each activity
        deduplicated_details = all_details.group_by(&:activity_id).map do |activity_id, records|
          records.max_by(&:updated_at)
        end

        # Convert to ActiveRecord relation for pagination
        UserDetail.where(id: deduplicated_details.map(&:id)).page(params[:page]).per(50)
      else
        UserDetail.none.page(params[:page]).per(50)
      end

    elsif current_user.role == "hod"
      # Get all user_details and deduplicate by activity and employee
      all_details = UserDetail.includes(:department, :activity, :employee_detail)
                            .assignment_consistent
                            .for_financial_year(selected_financial_year)

      # Deduplicate by keeping the most recent record for each activity-employee combination
      deduplicated_details = all_details.group_by { |detail| [ detail.activity_id, detail.employee_detail_id ] }.map do |key, records|
        records.max_by(&:updated_at)
      end

      # Convert to ActiveRecord relation for pagination
      @user_details = UserDetail.where(id: deduplicated_details.map(&:id)).page(params[:page]).per(50)
    end
  end

  def new
    @user_detail = UserDetail.new

    # Load unique departments
    @departments = Department.for_financial_year(selected_financial_year)
                             .select("MIN(id) AS id, department_type")
                             .group(:department_type)
                             .order(:department_type)
    selected_department = nil
    selected_department_type = nil
    @selected_department_record = nil

    # Filter employees based on selected department
    if params[:department_id].present?
      begin
        selected_department = Department.for_financial_year(selected_financial_year).find_by(id: params[:department_id]) ||
                              Department.find(params[:department_id])
        selected_department_type = selected_department.department_type
        @employee_details = eligible_employee_details_for_department(selected_department_type, selected_financial_year)
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = "Department not found."
        @employee_details = EmployeeDetail.none
      end
    else
      @employee_details = EmployeeDetail.none
    end

    # Find selected employee to show L1/L2
    if params[:employee_detail_id].present?
      begin
        @selected_employee = EmployeeDetail.find_by(id: params[:employee_detail_id])
        if @selected_employee.present? && selected_department_type.present? && @selected_employee.department != selected_department_type
          flash.now[:alert] = "Department badalne ke baad employee dobara select kijiye."
          @selected_employee = nil
        elsif @selected_employee.present? && @employee_details.present? && @employee_details.none? { |employee| employee.id == @selected_employee.id }
          flash.now[:notice] = "#{selected_department_type} ke liye sirf configured employees dikhaye ja rahe hain. Please list me se employee select kijiye."
          @selected_employee = nil
        end
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = "Employee not found."
        @selected_employee = nil
      end
    end

    @users = User.select(:id, :email, :role) if params[:show_users]

    # Load employee-specific activities when both department and employee are selected
    if params[:department_id].present? && params[:employee_detail_id].present?
      begin
        selected_department ||= Department.for_financial_year(selected_financial_year).find_by(id: params[:department_id]) ||
                                Department.find(params[:department_id])
        selected_department_type ||= selected_department.department_type
        @selected_department_record = department_for_employee(@selected_employee, selected_department_type, selected_financial_year)

        if @selected_employee.blank?
          @employee_activities = []
          @user_details = UserDetail.none
        elsif @selected_department_record.blank?
          flash.now[:alert] = "Selected employee ke liye #{selected_department_type} department setup nahi mila."
          @employee_activities = []
          @user_details = UserDetail.none
        else
          employee_details_for_department = UserDetail.includes(:department, :activity, :employee_detail)
                                                     .assignment_consistent
                                                     .for_financial_year(selected_financial_year)
                                                     .where(employee_detail_id: @selected_employee.id, department_id: @selected_department_record.id)
                                                     .where.not(activity_id: nil)
                                                     .to_a

          deduplicated_user_details = employee_details_for_department
            .group_by(&:activity_id)
            .values
            .map { |records| records.max_by(&:updated_at) }
            .compact

          @user_details = deduplicated_user_details.first(100)

          @employee_activities = if deduplicated_user_details.any?
            deduplicated_user_details.filter_map(&:activity).uniq(&:id)
          else
            @selected_department_record.activities
                                       .for_financial_year(selected_financial_year)
                                       .order(:activity_name)
          end
        end
      rescue ActiveRecord::RecordNotFound => e
        flash[:alert] = "Error loading data: #{e.message}"
        @employee_activities = []
        @user_details = UserDetail.none
      rescue => e
        flash[:alert] = "An error occurred while loading data."
        Rails.logger.error "Error in new action: #{e.message}"
        @employee_activities = []
        @user_details = UserDetail.none
      end
    else
      @employee_activities = []
      @user_details = UserDetail.none
    end

    @selected_department_type = selected_department_type
  end

  def create
    @user_detail = UserDetail.new(user_detail_params_with_financial_year)

    if @user_detail.save
      redirect_to new_user_detail_path(financial_year: @user_detail.financial_year), notice: "User detail was successfully created."
    else
      load_form_data
      render :new
    end
  end

  def edit
    @departments = Department.select(:id, :department_type)
    @activities = Activity.select(:id, :activity_name, :unit, :theme_name)
                         .where(department_id: @user_detail.department_id)
  end

  def update
    begin
      # Store the current context before update
      department_id = @user_detail.department_id
      employee_detail_id = @user_detail.employee_detail_id

      if @user_detail.update(user_detail_params_with_financial_year)
        # Clear any existing flash messages
        flash.clear

        # Role-based redirect
        if current_user.hod?
          # HOD redirects to new user detail form
          redirect_to new_user_detail_path(
                        department_id: department_id,
                        employee_detail_id: employee_detail_id,
                        financial_year: @user_detail.financial_year
                      ),
                      notice: "User detail was successfully updated."
        else
          # Employee/L1/L2 redirects to HOD TARGET FORM (index page)
          redirect_to user_details_path(financial_year: @user_detail.financial_year),
                      notice: "User detail was successfully updated."
        end
      else
        @departments = Department.select(:id, :department_type)
        @activities = Activity.select(:id, :activity_name, :unit, :theme_name)
                             .where(department_id: @user_detail.department_id)
        render :edit
      end
    rescue => e
      Rails.logger.error "Error in update action: #{e.message}"

      # Clear any existing flash messages
      flash.clear

      # Role-based error redirect
      if current_user.hod?
        redirect_to new_user_detail_path(financial_year: @user_detail.financial_year),
                    alert: "An error occurred while updating the user detail."
      else
        redirect_to user_details_path(financial_year: @user_detail.financial_year),
                    alert: "An error occurred while updating the user detail."
      end
    end
  end


  def update_quarterly_achievements
    requested_financial_year = UserDetail.normalize_financial_year(params[:financial_year]).presence || selected_financial_year
    # Get the correct parameters
    selected_quarter = params[:selected_quarter]
    achievement_data = params[:achievements] || {}
    success_count = 0
    errors = []
    updated_activities = []

    if achievement_data.empty?
      flash[:alert] = "No achievement data received. Please try again."
      redirect_to quarterly_edit_all_user_details_path(financial_year: requested_financial_year)
      return
    end

    # Define quarter months to limit updates to selected quarter only
    quarter_months = case selected_quarter
    when "Q1"
      [ "april", "may", "june" ]
    when "Q2"
      [ "july", "august", "september" ]
    when "Q3"
      [ "october", "november", "december" ]
    when "Q4"
      [ "january", "february", "march" ]
    else
      []
    end

    # Track which employee_details had changes to reset their quarter only
    employee_details_with_changes = Set.new

    ActiveRecord::Base.transaction do
      achievement_data.each do |user_detail_id, monthly_data|
        user_detail = UserDetail.find_by(id: user_detail_id)
        next unless user_detail

        activity_updated = false

        monthly_data.each do |month, values|
          # IMPORTANT: Only process months that belong to the selected quarter
          next unless quarter_months.include?(month)

          achievement_value = values[:achievement]
          employee_remarks = values[:employee_remarks]

          # Skip if both achievement and remarks are blank
          next if achievement_value.blank? && employee_remarks.blank?

          # Find or initialize achievement
          achievement = Achievement.find_or_initialize_by(
            user_detail: user_detail,
            month: month
          )

          # Store old values for comparison
          old_achievement = achievement.achievement
          old_remarks = achievement.employee_remarks

          # Update values
          achievement.achievement = achievement_value.present? ? achievement_value : nil
          achievement.employee_remarks = employee_remarks.present? ? employee_remarks : nil

          # Save if there are changes
          if achievement.achievement != old_achievement || achievement.employee_remarks != old_remarks
            if achievement.save
              success_count += 1
              activity_updated = true
              # Mark this employee_detail as having changes for quarterly status update
              employee_details_with_changes.add(user_detail.employee_detail_id)
            else
              error_msg = "Failed to save #{month.capitalize} for #{user_detail.activity.activity_name}: #{achievement.errors.full_messages.join(', ')}"
              errors << error_msg
            end
          end
        end

        if activity_updated
          activity_name = "#{user_detail.employee_detail&.employee_name} - #{user_detail.activity.activity_name}"
          updated_activities << activity_name
        end
      end

      # FIXED: Only set achievements to pending for employees who actually made changes
      # This ensures that only the specific employee's data gets reset to pending
      employee_details_with_changes.each do |employee_detail_id|
        employee_detail = EmployeeDetail.find(employee_detail_id)

        # Get all achievements for this specific employee in the selected quarter
        employee_achievements = Achievement.joins(:user_detail)
                                        .where(user_details: { employee_detail_id: employee_detail_id, financial_year: requested_financial_year })
                                        .where(month: quarter_months)

        # Set status to pending for this employee's achievements only
        updated_count = employee_achievements.update_all(status: "pending")

        # Also reset approval remarks for this employee's achievements
        employee_achievements.joins(:achievement_remark).each do |achievement|
          achievement.achievement_remark.update(
            l1_remarks: nil,
            l1_percentage: nil,
            l2_remarks: nil,
            l2_percentage: nil
          )
        end
      end
    end

    # Handle response messages
    if errors.empty?
      if success_count > 0
        affected_employees = employee_details_with_changes.map do |emp_id|
          EmployeeDetail.find(emp_id).employee_name
        end.join(", ")

        flash[:notice] = "✅ Updated #{success_count} records. Pending approval."
      else
        flash[:notice] = "No changes were made to the achievements."
      end
    else
      flash[:alert] = "⚠️ Some updates failed: #{errors.first(2).join('; ')}"
      flash[:alert] += " and #{errors.count - 2} more errors..." if errors.count > 2
    end

    redirect_to quarterly_edit_all_user_details_path(financial_year: requested_financial_year)

    rescue => e
      Rails.logger.error "Quarterly update error: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:alert] = "❌ An error occurred while updating achievements: #{e.message}"
      redirect_to quarterly_edit_all_user_details_path(financial_year: requested_financial_year)
  end

  # FIXED: Quarterly edit all method
  def quarterly_edit_all
    if current_user.role == "employee" || current_user.role == "l1_employer" || current_user.role == "l2_employer"
      employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)
      @user_details = if employee_detail
        UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                .assignment_consistent
                .for_financial_year(selected_financial_year)
                .where(employee_detail_id: employee_detail.id)
                .order("departments.department_type, activities.activity_name")
      else
        UserDetail.none
      end
    elsif current_user.role == "hod"
      @user_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                              .assignment_consistent
                              .for_financial_year(selected_financial_year)
                              .order("departments.department_type, employee_details.employee_name, activities.activity_name")
    else
      @user_details = UserDetail.none
    end


    # FIXED: Correct quarter definitions to match the system
    @quarters = [
      { name: "Q1", months: [ "april", "may", "june" ], label: "Q1 (Apr-Jun)" },
      { name: "Q2", months: [ "july", "august", "september" ], label: "Q2 (Jul-Sep)" },
      { name: "Q3", months: [ "october", "november", "december" ], label: "Q3 (Oct-Dec)" },
      { name: "Q4", months: [ "january", "february", "march" ], label: "Q4 (Jan-Mar)" }
    ]
  end


  def destroy
    begin
      @user_detail = UserDetail.find(params[:id])

      # Store the current context before deletion
      department_id = @user_detail.department_id
      employee_detail_id = @user_detail.employee_detail_id

      if @user_detail.destroy
        # Clear any existing flash messages
        flash.clear

        # Role-based redirect
        if current_user.hod?
          # HOD redirects to new user detail form
          redirect_to new_user_detail_path(
                        department_id: department_id,
                        employee_detail_id: employee_detail_id,
                        financial_year: @user_detail.financial_year
                      ),
                      notice: "User detail was successfully deleted."
        else
          # Employee/L1/L2 redirects to HOD TARGET FORM (index page)
          redirect_to user_details_path(financial_year: @user_detail.financial_year),
                      notice: "User detail was successfully deleted."
        end
      else
        # Clear any existing flash messages
        flash.clear

        # Role-based error redirect
        if current_user.hod?
          redirect_to new_user_detail_path(financial_year: @user_detail.financial_year),
                      alert: "Failed to delete user detail."
        else
          redirect_to user_details_path(financial_year: @user_detail.financial_year),
                      alert: "Failed to delete user detail."
        end
      end
    rescue ActiveRecord::RecordNotFound
      # Clear any existing flash messages
      flash.clear

      # Role-based error redirect
      if current_user.hod?
        redirect_to new_user_detail_path(financial_year: selected_financial_year),
                    alert: "User detail not found."
      else
        redirect_to user_details_path(financial_year: selected_financial_year),
                    alert: "User detail not found."
      end
    rescue => e
      Rails.logger.error "Error in destroy action: #{e.message}"

      # Clear any existing flash messages
      flash.clear

      # Role-based error redirect
      if current_user.hod?
        redirect_to new_user_detail_path(financial_year: selected_financial_year),
                    alert: "An error occurred while deleting the user detail."
      else
        redirect_to user_details_path(financial_year: selected_financial_year),
                    alert: "An error occurred while deleting the user detail."
      end
    end
  end

  def test_sms
    # Test SMS functionality directly
    begin
      # Find a real employee detail record that has L1 code and mobile number
      test_employee = EmployeeDetail.joins(:user_detail)
                                   .where.not(l1_code: [ nil, "" ])
                                   .where.not(mobile_number: [ nil, "" ])
                                   .first

      if test_employee.nil?
        flash[:alert] = "❌ No employee found with L1 code and mobile number for testing"
        redirect_to get_user_detail_user_details_path(financial_year: selected_financial_year)
        return
      end

      # Find the L1 manager
      l1_manager = EmployeeDetail.find_by("employee_code LIKE ?", test_employee.l1_code.strip + "%")

      if l1_manager.nil?
        flash[:alert] = "❌ L1 manager not found with code: #{test_employee.l1_code}"
        redirect_to get_user_detail_user_details_path(financial_year: selected_financial_year)
        return
      end

      if l1_manager.mobile_number.blank?
        flash[:alert] = "❌ L1 manager #{l1_manager.employee_name} has no mobile number"
        redirect_to get_user_detail_user_details_path(financial_year: selected_financial_year)
        return
      end

      # Test with Q1 quarter
      result = send_sms_to_l1(test_employee, "Q1 (APR-JUN)", nil)

      if result[:success]
        flash[:notice] = "✅ Test SMS sent successfully! Message ID: #{result[:message_id]}"
      else
        flash[:alert] = "❌ Test SMS failed: #{result[:error]}"
        Rails.logger.error "Test SMS failed: #{result.inspect}"
      end

    rescue => e
      flash[:alert] = "❌ Test SMS error: #{e.message}"
      Rails.logger.error "Test SMS error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    end

    redirect_to get_user_detail_user_details_path(financial_year: selected_financial_year)
  end

  def get_user_detail
    if [ "employee", "l1_employer", "l2_employer" ].include?(current_user.role)
      @employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if @employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                               .assignment_consistent
                               .for_financial_year(selected_financial_year)
                               .where(employee_detail_id: @employee_detail.id)

        # Deduplicate by keeping the most recent record for each activity
        deduplicated_details = all_details.group_by(&:activity_id).map do |activity_id, records|
          records.max_by(&:updated_at)
        end

        # Convert to ActiveRecord relation and keep review data preloaded for quarter summaries
        UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                  .where(id: deduplicated_details.map(&:id))
                  .limit(100)
      else
        UserDetail.none
      end

    elsif current_user.role == "hod"
      # Get all user_details and deduplicate by activity and employee
      all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                             .assignment_consistent
                             .for_financial_year(selected_financial_year)

      # Deduplicate by keeping the most recent record for each activity-employee combination
      deduplicated_details = all_details.group_by { |detail| [ detail.activity_id, detail.employee_detail_id ] }.map do |key, records|
        records.max_by(&:updated_at)
      end

      # Convert to ActiveRecord relation and keep review data preloaded for quarter summaries
      @user_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                                .where(id: deduplicated_details.map(&:id))
                                .limit(100)
      @employee_detail = nil
    end
  end

  def submitted_achievements
    if [ "employee", "l1_employer", "l2_employer" ].include?(current_user.role)
      @employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if @employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                               .assignment_consistent
                               .for_financial_year(selected_financial_year)
                               .where(employee_detail_id: @employee_detail.id)

        # Deduplicate by keeping the most recent record for each activity
        deduplicated_details = all_details.group_by(&:activity_id).map do |activity_id, records|
          records.max_by(&:updated_at)
        end

        # Convert to ActiveRecord relation and limit
        UserDetail.where(id: deduplicated_details.map(&:id)).limit(100)
      else
        UserDetail.none
      end

    elsif current_user.role == "hod"
      # Get all user_details and deduplicate by activity and employee
      all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                             .assignment_consistent
                             .for_financial_year(selected_financial_year)

      # Deduplicate by keeping the most recent record for each activity-employee combination
      deduplicated_details = all_details.group_by { |detail| [ detail.activity_id, detail.employee_detail_id ] }.map do |key, records|
        records.max_by(&:updated_at)
      end

      # Convert to ActiveRecord relation and limit
      @user_details = UserDetail.where(id: deduplicated_details.map(&:id)).limit(100)
      @employee_detail = nil
    end
  end

  def submit_achievements
    begin
      achievement_data = params[:achievement] || {}
      success_count = 0
      sms_results = []
      processed_employees = Set.new


      ActiveRecord::Base.transaction do
        achievement_data.each do |user_detail_id, monthly_data|
          user_detail = UserDetail.find_by(id: user_detail_id)
          next unless user_detail

          employee_detail = user_detail.employee_detail
          next unless employee_detail

          monthly_data.each do |month, values|
            achievement_value = values[:achievement]
            employee_remarks = values[:employee_remarks]

            next if achievement_value.blank?

            target_value = user_detail.send(month)
            next if target_value.blank?

            achievement = Achievement.find_or_initialize_by(
              user_detail: user_detail,
              month: month
            )

            achievement.achievement = achievement_value
            achievement.employee_remarks = employee_remarks
            achievement.status = "pending"

            if achievement.save
              success_count += 1
            end
          end

          # Send SMS only once per employee per quarter
          unless processed_employees.include?(employee_detail.id)
            processed_employees.add(employee_detail.id)

            quarters_filled = Set.new
            monthly_data.each do |month, values|
              next if values[:achievement].blank?
              quarter = determine_quarter(month)
              quarters_filled.add(quarter) if quarter.present?
            end

            quarters_filled.each do |quarter|
              sms_already_sent = check_sms_already_sent(employee_detail.id, quarter)

              unless sms_already_sent
                sms_result = send_sms_to_l1(employee_detail, quarter, user_detail)
                sms_results << {
                  quarter: quarter,
                  employee: employee_detail.employee_name,
                  success: sms_result[:success],
                  message: sms_result[:success] ? "SMS sent successfully" : sms_result[:error]
                }

                mark_sms_as_sent(employee_detail.id, quarter) if sms_result[:success]
              end
            end
          end
        end
      end

      # Prepare response message
      response_message = "Achievements submitted successfully. #{success_count} records updated."
      if sms_results.any?
        successful_sms = sms_results.select { |r| r[:success] }
        if successful_sms.any?
          response_message += " 📱 SMS notifications sent for #{successful_sms.count} quarter(s)."
        end
      end

      render json: {
        success: true,
        count: success_count,
        sms_results: sms_results,
        message: response_message
      }
    rescue => e
      Rails.logger.error "Achievement submission failed: #{e.message}"
      Rails.logger.error "Error class: #{e.class}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"

      error_response = {
        success: false,
        error: "Achievement submission failed: #{e.message}",
        message: "There was an error submitting achievements. Please try again."
      }

      Rails.logger.error "Error response prepared: #{error_response.inspect}"

      render json: error_response, status: :internal_server_error
    end
  end

  def get_activities
    department_id = params[:department_id]

    if department_id.present?
      activities = Activity.select(:id, :activity_name, :unit, :weight, :theme_name)
                          .where(department_id: department_id)

      activities_data = activities.map do |activity|
        {
          id: activity.id,
          activity_name: activity.activity_name,
          unit: activity.unit,
          weight: activity.weight,
          theme_name: activity.theme_name
        }
      end

      render json: activities_data
    else
      render json: { error: "Department ID is required" }, status: :bad_request
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Department not found" }, status: :not_found
  rescue => e
    render json: { error: "An error occurred while fetching activities" }, status: :internal_server_error
  end

  def bulk_create
    department_id = params[:department_id]
    employee_detail_id = params[:employee_detail_id]
    financial_year = UserDetail.normalize_financial_year(params[:financial_year]).presence || selected_financial_year
    user_details_params = params[:user_details]
    redirect_path = new_user_detail_path(
      department_id: department_id,
      employee_detail_id: employee_detail_id,
      financial_year: financial_year
    )

    # Enhanced validation
    if department_id.blank?
      respond_to do |format|
        format.html { redirect_to new_user_detail_path(financial_year: financial_year), alert: "Department ID is required", status: :see_other }
        format.turbo_stream { redirect_to new_user_detail_path(financial_year: financial_year), alert: "Department ID is required", status: :see_other }
        format.json { render json: { error: "Department ID is required" }, status: :bad_request }
      end
      return
    end

    if employee_detail_id.blank?
      respond_to do |format|
        format.html { redirect_to redirect_path, alert: "Employee Detail ID is required", status: :see_other }
        format.turbo_stream { redirect_to redirect_path, alert: "Employee Detail ID is required", status: :see_other }
        format.json { render json: { error: "Employee Detail ID is required" }, status: :bad_request }
      end
      return
    end

    if user_details_params.blank?
      respond_to do |format|
        format.html { redirect_to redirect_path, alert: "No user details provided", status: :see_other }
        format.turbo_stream { redirect_to redirect_path, alert: "No user details provided", status: :see_other }
        format.json { render json: { error: "No user details provided" }, status: :bad_request }
      end
      return
    end

    department = Department.for_financial_year(financial_year).find_by(id: department_id) || Department.find_by(id: department_id)
    unless department
      respond_to do |format|
        format.html { redirect_to new_user_detail_path(financial_year: financial_year), alert: "Department not found", status: :see_other }
        format.turbo_stream { redirect_to new_user_detail_path(financial_year: financial_year), alert: "Department not found", status: :see_other }
        format.json { render json: { error: "Department not found" }, status: :not_found }
      end
      return
    end

    employee_detail = EmployeeDetail.find_by(id: employee_detail_id)
    unless employee_detail
      respond_to do |format|
        format.html { redirect_to redirect_path, alert: "Employee not found", status: :see_other }
        format.turbo_stream { redirect_to redirect_path, alert: "Employee not found", status: :see_other }
        format.json { render json: { error: "Employee not found" }, status: :not_found }
      end
      return
    end

    actual_department = department_for_employee(employee_detail, department.department_type, financial_year)
    if actual_department.blank? || actual_department.id != department.id
      mismatch_message = "Selected department is not assigned to the chosen employee."

      respond_to do |format|
        format.html { redirect_to redirect_path, alert: mismatch_message, status: :see_other }
        format.turbo_stream { redirect_to redirect_path, alert: mismatch_message, status: :see_other }
        format.json { render json: { error: mismatch_message }, status: :unprocessable_entity }
      end
      return
    end

    created_count = 0
    updated_count = 0
    errors = []

    ActiveRecord::Base.transaction do
      user_details_params.each do |activity_id, details|
        begin
          activity = Activity.find_by(id: activity_id)
          unless activity
            errors << "Activity with ID #{activity_id} not found"
            next
          end

          if activity.department_id != department.id
            errors << "Activity #{activity_id} does not belong to the selected department"
            next
          end

          # Extract monthly data
          month_data = {
            april: extract_month_value(details, "april"),
            may: extract_month_value(details, "may"),
            june: extract_month_value(details, "june"),
            july: extract_month_value(details, "july"),
            august: extract_month_value(details, "august"),
            september: extract_month_value(details, "september"),
            october: extract_month_value(details, "october"),
            november: extract_month_value(details, "november"),
            december: extract_month_value(details, "december"),
            january: extract_month_value(details, "january"),
            february: extract_month_value(details, "february"),
            march: extract_month_value(details, "march")
          }

          # Extract activity metadata (unit and theme_name)
          # Handle blank values properly - convert empty strings to nil for database
          unit_value = details["unit"] || details[:unit]
          theme_value = details["theme_name"] || details[:theme_name]

          activity_metadata = {
            unit: unit_value.present? ? unit_value : nil,
            theme_name: theme_value.present? ? theme_value : nil
          }

          # Use find_or_initialize_by to prevent duplicates
          user_detail_record = UserDetail.find_or_initialize_by(
            department_id: department.id,
            activity_id: activity_id,
            employee_detail_id: employee_detail.id,
            financial_year: financial_year
          )

          # Update Activity metadata (always update to handle clearing values)
          activity_update_data = {}

          # Always include unit and theme_name in update (nil values will clear the fields)
          activity_update_data[:unit] = activity_metadata[:unit]
          activity_update_data[:theme_name] = activity_metadata[:theme_name]

          unless activity.update(activity_update_data)
            errors << "Failed to update activity metadata for activity #{activity_id}: #{activity.errors.full_messages.join(', ')}"
          end

          # Store a yearly snapshot so previous financial years keep their own values.
          user_detail_record.assign_attributes(
            month_data.merge(
              theme_name: activity_metadata[:theme_name],
              unit: activity_metadata[:unit]
            )
          )

          if user_detail_record.save
            if user_detail_record.previously_new_record?
              created_count += 1
            else
              updated_count += 1
            end
          else
            errors << "Failed to save activity #{activity_id}: #{user_detail_record.errors.full_messages.join(', ')}"
          end
        rescue => e
          errors << "Error processing activity #{activity_id}: #{e.message}"
        end
      end

      if errors.present? && (created_count + updated_count) == 0
        raise ActiveRecord::Rollback
      end
    end

    if errors.empty? || (created_count + updated_count) > 0
      message = []
      message << "#{created_count} records created" if created_count > 0
      message << "#{updated_count} records updated" if updated_count > 0
      message = [ "No changes made" ] if message.empty?

      success_message = message.join(", ")
      success_message = "#{success_message}. Warnings: #{errors.first(2).join('; ')}" if errors.present?

      response_data = {
        success: true,
        message: success_message,
        created: created_count,
        updated: updated_count,
        financial_year: financial_year
      }

      response_data[:warnings] = errors if errors.present?

      respond_to do |format|
        format.html { redirect_to redirect_path, notice: success_message, status: :see_other }
        format.turbo_stream { redirect_to redirect_path, notice: success_message, status: :see_other }
        format.json { render json: response_data }
      end
    else
      failure_message = if errors.present?
        "Failed to save records: #{errors.first(3).join('; ')}"
      else
        "Failed to save records"
      end

      respond_to do |format|
        format.html { redirect_to redirect_path, alert: failure_message, status: :see_other }
        format.turbo_stream { redirect_to redirect_path, alert: failure_message, status: :see_other }
        format.json do
          render json: {
            success: false,
            error: "Failed to save records",
            errors: errors,
            created: created_count,
            updated: updated_count
          }, status: :unprocessable_entity
        end
      end
    end
  end

  def export
    @user_details = UserDetail.includes(:employee_detail, :department, :activity)
                              .assignment_consistent
                              .for_financial_year(selected_financial_year)
                              .limit(5000)

    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=\"user_details_#{selected_financial_year.tr('-', '_')}.xlsx\""
      }
    end
  end

  def export_department_activity_data
    requested_financial_year = UserDetail.normalize_financial_year(params[:financial_year]).presence || selected_financial_year

    if params[:department_id].blank? || params[:employee_detail_id].blank?
      @user_details = UserDetail.includes(:employee_detail, :department, :activity)
                                .assignment_consistent
                                .for_financial_year(requested_financial_year)
                                .where.not(activity_id: nil)
                                .limit(5000)
                                .to_a
                                .group_by { |detail| [ detail.employee_detail_id, detail.department_id, detail.activity_id ] }
                                .values
                                .map { |records| records.max_by(&:updated_at) }
                                .compact
                                .sort_by do |detail|
                                  [
                                    detail.employee_detail&.employee_name.to_s.downcase,
                                    detail.department&.department_type.to_s.downcase,
                                    detail.activity&.activity_name.to_s.downcase
                                  ]
                                end

      filename_prefix = @user_details.any? ? "department_activity_data" : "department_activity_template"

      respond_to do |format|
        format.xlsx {
          response.headers["Content-Disposition"] = "attachment; filename=\"#{filename_prefix}_#{requested_financial_year.tr('-', '_')}.xlsx\""
        }
      end
      return
    end

    selected_department = Department.for_financial_year(requested_financial_year).find_by(id: params[:department_id]) ||
                          Department.find_by(id: params[:department_id])
    unless selected_department
      redirect_to new_user_detail_path(financial_year: selected_financial_year), alert: "Selected department was not found."
      return
    end

    selected_employee = EmployeeDetail.find_by(id: params[:employee_detail_id])
    unless selected_employee
      redirect_to new_user_detail_path(financial_year: selected_financial_year), alert: "Selected employee was not found."
      return
    end

    actual_department = department_for_employee(selected_employee, selected_department.department_type, requested_financial_year)
    unless actual_department
      redirect_to new_user_detail_path(financial_year: selected_financial_year), alert: "Selected department does not belong to the chosen employee."
      return
    end

    @user_details = UserDetail.includes(:employee_detail, :department, :activity)
                              .assignment_consistent
                              .for_financial_year(requested_financial_year)
                              .where(
                                employee_detail_id: selected_employee.id,
                                department_id: actual_department.id
                              )
                              .where.not(activity_id: nil)
                              .limit(5000)
                              .to_a
                              .group_by(&:activity_id)
                              .values
                              .map { |records| records.max_by(&:updated_at) }
                              .compact
                              .sort_by { |detail| detail.activity&.activity_name.to_s.downcase }

    if @user_details.blank?
      export_activities = actual_department.activities
                                           .for_financial_year(requested_financial_year)
                                           .order(:activity_name)
                                           .to_a

      if export_activities.blank?
        redirect_to new_user_detail_path(
          department_id: params[:department_id],
          employee_detail_id: params[:employee_detail_id],
          financial_year: requested_financial_year
        ), alert: "No activities found to export for the selected department and employee."
        return
      end

      @user_details = export_activities.map do |activity|
        UserDetail.new(
          financial_year: requested_financial_year,
          department: actual_department,
          employee_detail: selected_employee,
          activity: activity,
          theme_name: activity.theme_name,
          unit: activity.unit
        )
      end
    end

    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=\"department_activity_data_#{requested_financial_year.tr('-', '_')}.xlsx\""
      }
    end
  end

  def import
    file = params[:file]
    requested_financial_year = UserDetail.normalize_financial_year(params[:financial_year]).presence || selected_financial_year

    unless file && [ ".xlsx", ".xls" ].include?(File.extname(file.original_filename))
      redirect_to new_user_detail_path(financial_year: requested_financial_year), alert: "Please upload a valid .xlsx or .xls file."
      return
    end

    begin
      spreadsheet = Roo::Spreadsheet.open(file.tempfile.path, extension: File.extname(file.original_filename).delete("."))
      header = spreadsheet.row(1)

      errors = []
      success_count = 0
      skipped_blank_rows = 0
      batch_size = 100

      # Process in batches for better performance
      (2..spreadsheet.last_row).each_slice(batch_size) do |rows|
        ActiveRecord::Base.transaction do
          rows.each do |i|
            row_data = spreadsheet.row(i)
            row = {}
            header.each_with_index do |col_name, index|
              next if col_name.nil?
              key = col_name.to_s.strip.downcase.gsub(/\s+/, "_")
              row[key] = row_data[index]
            end

            if row_blank_for_user_detail_import?(row)
              skipped_blank_rows += 1
              next
            end

            employee_name = row["employee_name"]
            employee_email = row["employee_email"]
            employee_code = row["employee_code"]

            mobile_number = extract_employee_mobile_number(row)

            l1_code = row["l1_code"] || row["l1_employer_code"]
            l1_employer_name = row["l1_employer_name"]
            l2_code = row["l2_code"] || row["l2_employer_code"]
            l2_employer_name = row["l2_employer_name"]
            department_type = row["department"]
            activity_name = row["activity_name"]
            activity_theme_name = row["theme_name"] || row["theme"] || row["activity_theme"]
            unit = row["unit"]

            months = {
              april: normalize_percentage(row["april"]),
              may: normalize_percentage(row["may"]),
              june: normalize_percentage(row["june"]),
              july: normalize_percentage(row["july"]),
              august: normalize_percentage(row["august"]),
              september: normalize_percentage(row["september"]),
              october: normalize_percentage(row["october"]),
              november: normalize_percentage(row["november"]),
              december: normalize_percentage(row["december"]),
              january: normalize_percentage(row["january"]),
              february: normalize_percentage(row["february"]),
              march: normalize_percentage(row["march"])
            }



            if employee_name.blank?
              errors << "Row #{i}: Employee name is missing"
              next
            end

            if department_type.blank?
              errors << "Row #{i}: Department is missing"
              next
            end

            if activity_name.blank?
              errors << "Row #{i}: Activity name is missing"
              next
            end

            department = Department.find_or_create_by!(department_type: department_type)

            employee_attributes = {
              employee_name: employee_name.to_s.strip,
              employee_email: employee_email.to_s.strip,
              employee_code: employee_code.to_s.strip,
              mobile_number: mobile_number.to_s.strip,
              l1_code: l1_code.to_s.strip,
              l2_code: l2_code.to_s.strip,
              l1_employer_name: l1_employer_name.to_s.strip,
              l2_employer_name: l2_employer_name.to_s.strip,
              department: department_type.to_s.strip
            }.reject { |_, value| value.blank? }

            employee = find_employee_for_user_detail_import(employee_attributes) || EmployeeDetail.new(employee_id: SecureRandom.uuid, post: "Imported")
            employee.assign_attributes(employee_attributes)
            employee.post = "Imported" if employee.post.blank?
            employee.save!

            activity = Activity.find_or_create_by!(
              activity_name: activity_name.strip,
              department_id: department.id
            ) do |a|
              a.unit = unit
              a.weight = 1.0
              a.theme_name = activity_theme_name.to_s.strip if activity_theme_name.present?
            end

            # Update theme_name if provided and different
            if activity_theme_name.present? && activity.theme_name != activity_theme_name.strip
              activity.update(theme_name: activity_theme_name.strip)
            end

            row_financial_year = UserDetail.normalize_financial_year(row["financial_year"]).presence || requested_financial_year

            begin
              user_detail = UserDetail.find_or_initialize_by(
                employee_detail_id: employee.id,
                department_id: department.id,
                activity_id: activity.id,
                financial_year: row_financial_year
              )
              user_detail.assign_attributes(
                months.merge(
                  theme_name: activity_theme_name.present? ? activity_theme_name.to_s.strip : activity.theme_name,
                  unit: unit.present? ? unit.to_s.strip : activity.unit
                )
              )
              user_detail.save!
              success_count += 1
            rescue ActiveRecord::RecordInvalid => e
              errors << "Row #{i}: #{e.message}"
            end
          end
        end
      end

      if errors.any?
        if success_count > 0
          redirect_to new_user_detail_path(financial_year: requested_financial_year), alert: "Partially imported: #{success_count} records saved, but #{errors.count} errors:\n#{errors.first(10).join("\n")}"
        else
          redirect_to new_user_detail_path(financial_year: requested_financial_year), alert: "Import failed. Errors:\n#{errors.first(10).join("\n")}"
        end
      elsif success_count.zero?
        redirect_to new_user_detail_path(financial_year: requested_financial_year), alert: "Import file contains no filled data rows. Please enter data in the Excel file before uploading."
      else
        notice_message = "Excel file imported successfully! #{success_count} records processed."
        notice_message += " #{skipped_blank_rows} blank rows skipped." if skipped_blank_rows.positive?
        redirect_to new_user_detail_path(financial_year: requested_financial_year), notice: notice_message
      end

    rescue => e
      Rails.logger.error "Import error: #{e.message}\n#{e.backtrace.join("\n")}"
      redirect_to new_user_detail_path(financial_year: requested_financial_year), alert: "Error reading Excel file: #{e.message}"
    end
  end



  private

  def extract_employee_mobile_number(row)
    prioritized_keys = %w[
      employee_mobile_number
      employee_mobile
      employee_mobile_no
      mobile_number
      mobile_no
      mobile
      mobile_number.
      mobile_no.
      mobile.
      mobile_number_
      mobile_no_
      mobile_
    ]

    prioritized_keys.each do |key|
      value = row[key]
      return value if value.present?
    end

    row.each do |key, value|
      normalized_key = key.to_s.downcase.gsub(/[^a-z0-9]/, "")
      next unless normalized_key.include?("mobile")
      next if normalized_key.include?("l1") || normalized_key.include?("l2")

      return value if value.present?
    end

    nil
  end

  def row_blank_for_user_detail_import?(row)
    row.values.all? do |value|
      value.blank? || (value.is_a?(String) && value.strip.blank?)
    end
  end

  def find_employee_for_user_detail_import(employee_attributes)
    if employee_attributes[:employee_code].present?
      employee = EmployeeDetail.find_by(employee_code: employee_attributes[:employee_code])
      return employee if employee
    end

    if employee_attributes[:employee_email].present?
      employee = EmployeeDetail.find_by(employee_email: employee_attributes[:employee_email])
      return employee if employee
    end

    if employee_attributes[:employee_name].present? && employee_attributes[:department].present?
      employee = EmployeeDetail.find_by(
        employee_name: employee_attributes[:employee_name],
        department: employee_attributes[:department]
      )
      return employee if employee
    end

    nil
  end

  def set_user_detail
    @user_detail = UserDetail.find(params[:id])
  end

  def department_for_employee(employee, department_type, financial_year)
    return if employee.blank? || department_type.blank?

    references = [ employee.employee_id, employee.employee_code ].compact_blank
    scope = Department.for_financial_year(financial_year).where(department_type: department_type)

    if references.any?
      specific_department = scope.where(employee_reference: references).order(:id).first
      return specific_department if specific_department
    end

    scope.where(employee_reference: [ nil, "" ]).order(:id).first
  end

  def eligible_employee_details_for_department(department_type, financial_year)
    return EmployeeDetail.none if department_type.blank?

    normalized_year = UserDetail.normalize_financial_year(financial_year).presence || UserDetail.current_financial_year
    employee_scope = EmployeeDetail.where(department: department_type)

    generic_department_exists = Department.for_financial_year(normalized_year)
                                         .where(department_type: department_type, employee_reference: [ nil, "" ])
                                         .exists?

    unless generic_department_exists
      join_sql = ActiveRecord::Base.send(
        :sanitize_sql_array,
        [
          "INNER JOIN departments matching_departments ON matching_departments.financial_year = ? AND matching_departments.department_type = ? AND (matching_departments.employee_reference = employee_details.employee_id OR matching_departments.employee_reference = employee_details.employee_code)",
          normalized_year,
          department_type
        ]
      )

      employee_scope = employee_scope.joins(join_sql).distinct
    end

    employee_scope.select(:id, :employee_name, :l1_employer_name, :l2_employer_name, :department)
                  .order(:employee_name)
  end

  def user_detail_params
    params.require(:user_detail).permit(:department_id, :activity_id, :april, :may, :june,
                                        :july, :august, :september, :october, :november,
                                        :december, :january, :february, :march, :employee_detail_id,
                                        :employee_detail_email, :financial_year, :theme_name, :unit)
  end

  def bulk_create_params
    params.permit(:department_id, :employee_detail_id, user_details: {})
  end

  def extract_month_value(details, month)
    return nil if details.blank?

    value = details[month] || details[month.to_sym] || details[month.to_s]

    return nil if value.blank?
    return value.to_f if value.is_a?(String) && value.match?(/^\d+\.?\d*$/)
    value
  end

  def normalize_percentage(value)
    return nil if value.nil?

    # FIXED: Don't convert values to percentages automatically
    # Only convert if explicitly marked as percentage
    if value.is_a?(String)
      # Remove any whitespace
      cleaned_value = value.strip
      return nil if cleaned_value.blank?

      # Handle percentage values (only if they contain % symbol)
      if cleaned_value.include?("%")
        return cleaned_value.gsub("%", "").to_f
      end

      # Handle numeric strings - return as is, don't convert to percentage
      if cleaned_value.match?(/^\d+\.?\d*$/)
        return cleaned_value.to_f
      end

      # Return the original string if it's not numeric
      cleaned_value
    elsif value.is_a?(Numeric)
      # FIXED: Don't automatically convert numbers to percentages
      # Only convert if the value is explicitly a decimal percentage (0.0 to 1.0)
      # AND it's marked as a percentage in the original data
      value
    else
      # For other types, try to convert to string and then process
      normalize_percentage(value.to_s)
    end
  end

  def load_form_data
    @departments = Department.for_financial_year(selected_financial_year)
                             .select("MIN(id) AS id, department_type")
                             .group(:department_type)
                             .order(:department_type)
    @activities = @user_detail.department_id.present? ?
                  Activity.select(:id, :activity_name, :unit, :theme_name)
                         .where(department_id: @user_detail.department_id) : []
    selected_year = @user_detail&.financial_year.presence || selected_financial_year
    @user_details = UserDetail.includes(:department, :activity)
                              .assignment_consistent
                              .for_financial_year(selected_year)
                              .limit(100)
  end

  def filter_conditions
    conditions = {}

    if params[:department_id].present?
      conditions[:department_id] = params[:department_id]
    end

    if params[:employee_detail_id].present?
      conditions[:employee_detail_id] = params[:employee_detail_id]
    end

    conditions
  end

  def user_detail_params_with_financial_year
    user_detail_params.merge(
      financial_year: UserDetail.normalize_financial_year(user_detail_params[:financial_year]).presence ||
                      @user_detail&.financial_year ||
                      selected_financial_year
    )
  end

  # SMS functionality for quarterly notifications
  def send_sms_to_l1(employee_detail, quarter, user_detail)
    begin
      # Get L1 manager's mobile number (not the employee's mobile number)
      l1_code = employee_detail.l1_code
      return { success: false, error: "L1 code not found for employee" } unless l1_code.present?
      normalized_l1_code = l1_code.to_s.strip

      # Find the L1 manager's employee detail record
      l1_manager = EmployeeDetail.find_by(employee_code: normalized_l1_code) ||
                   EmployeeDetail.find_by("employee_code LIKE ?", normalized_l1_code + "%")
      return { success: false, error: "L1 manager not found with code: #{normalized_l1_code}" } unless l1_manager.present?

      l1_mobile = l1_manager.mobile_number
      return { success: false, error: "L1 manager mobile number not found" } unless l1_mobile.present?

      # Clean and validate mobile number
      l1_mobile = l1_mobile.to_s.strip.gsub(/\D/, "")
      l1_mobile = l1_mobile[-10, 10] if l1_mobile.length > 10
      return { success: false, error: "Invalid mobile number format" } unless l1_mobile.length == 10

      # Prepare the message exactly as per the working API example
      message = "Emp-Code: #{employee_detail.employee_code}, Emp-Name: #{employee_detail.employee_name} has submitted his #{quarter} Qtr KRA MIS. Please review and approve in the system. Ploughman Agro Private Limited"

      # Prepare API parameters using the exact working API
      params = {
        authkey: "37317061706c39353312",
        mobiles: l1_mobile,
        message: message,
        sender: "PLOAPL",
        route: "2",
        country: "0",
        DLT_TE_ID: "1707175594432371766",
        unicode: "1"
      }

      # Build the API URL
      api_url = "https://sms.yoursmsbox.com/api/sendhttp.php"

      # Send SMS using HTTParty (which is already in Gemfile)
      require "httparty"
      Rails.logger.info(
        "Sending SMS to L1 manager: employee_code=#{employee_detail.employee_code}, " \
        "employee_name=#{employee_detail.employee_name}, quarter=#{quarter}, " \
        "l1_code=#{normalized_l1_code}, l1_manager_id=#{l1_manager.id}, " \
        "l1_manager_name=#{l1_manager.employee_name}, l1_mobile=#{l1_mobile}"
      )
      response = HTTParty.get(api_url, query: params, timeout: 15)
      Rails.logger.info "SMS API response: HTTP #{response.code} - #{response.body}"

      if response.success?
        # Parse the JSON response to check if SMS was actually sent
        begin
          response_data = JSON.parse(response.body)
          if response_data["Status"] == "Success" && response_data["Code"] == "000"
            {
              success: true,
              message: "SMS sent successfully",
              message_id: response_data["Message-Id"],
              target_mobile: l1_mobile,
              target_name: l1_manager.employee_name,
              response: response_data
            }
          else
            Rails.logger.error "SMS API returned error: #{response_data}"
            {
              success: false,
              error: "SMS API error: #{response_data['Description'] || response_data['Status']}",
              target_mobile: l1_mobile,
              target_name: l1_manager.employee_name
            }
          end
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse SMS API response: #{e.message}"
          { success: false, error: "Invalid SMS API response format: #{response.body}", target_mobile: l1_mobile, target_name: l1_manager.employee_name }
        end
      else
        Rails.logger.error "SMS API HTTP error: #{response.code} - #{response.body}"
        { success: false, error: "SMS API HTTP error: #{response.code} - #{response.body}", target_mobile: l1_mobile, target_name: l1_manager.employee_name }
      end

    rescue => e
      Rails.logger.error "SMS service error: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      { success: false, error: "SMS service error: #{e.message}" }
    end
  end

  def determine_quarter(month)
    case month.to_s.downcase
    when "april", "may", "june"
      "Q1 (APR-JUN)"
    when "july", "august", "september"
      "Q2 (JUL-SEP)"
    when "october", "november", "december"
      "Q3 (OCT-DEC)"
    when "january", "february", "march"
      "Q4 (JAN-MAR)"
    else
      nil
    end
  end

  def clear_sms_tracking
    # Clear SMS tracking for a fresh start
    # Clear all SMS logs since we're tracking per employee
    SmsLog.destroy_all
    flash[:notice] = "SMS tracking cleared. New SMS will be sent for each quarter."
    redirect_to get_user_detail_user_details_path(financial_year: selected_financial_year)
  end

  def view_sms_logs
    # View SMS logs to see which SMS have been sent
    @sms_logs = SmsLog.includes(:employee_detail).order(created_at: :desc).limit(50)
    render :view_sms_logs
  end

  public :clear_sms_tracking, :view_sms_logs

  def check_sms_already_sent(employee_detail_id, quarter)
    # Check if SMS was already sent for this quarter using database
    # Use employee_detail_id to track per employee, not per activity
    SmsLog.exists?(employee_detail_id: employee_detail_id, quarter: quarter, sent: true)
  end

  def mark_sms_as_sent(employee_detail_id, quarter)
    # Mark SMS as sent in database to prevent duplicates
    # Use employee_detail_id to track per employee, not per activity
    sms_log = SmsLog.find_or_initialize_by(
      employee_detail_id: employee_detail_id,
      quarter: quarter
    )
    sms_log.sent = true
    sms_log.sent_at ||= Time.current
    sms_log.save!
  rescue => e
    Rails.logger.error "Failed to mark SMS as sent: #{e.message}"
  end
end
