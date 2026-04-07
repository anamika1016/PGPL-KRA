class UserDetailsController < ApplicationController
  require "ostruct"
  require "set"
  before_action :set_user_detail, only: [ :show, :edit, :update, :destroy ]
  load_and_authorize_resource except: [ :index, :new, :create, :get_user_detail, :get_activities, :bulk_create, :submit_achievements, :export, :import, :quarterly_edit_all, :update_quarterly_achievements, :test_sms, :view_sms_logs, :submitted_achievements ]

  def index
    if current_user.role == "employee" || current_user.role == "l1_employer" || current_user.role == "l2_employer"
      employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail)
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
    @departments = Department.select("DISTINCT ON (department_type) id, department_type")

    # Filter employees based on selected department
    if params[:department_id].present?
      begin
        dept_type = Department.find(params[:department_id]).department_type
        @employee_details = EmployeeDetail.where(department: dept_type)
                                          .select(:id, :employee_name, :l1_employer_name, :l2_employer_name, :department)
                                          .order(:employee_name)
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
      rescue ActiveRecord::RecordNotFound
        flash[:alert] = "Employee not found."
        @selected_employee = nil
      end
    end

    @users = User.select(:id, :email, :role) if params[:show_users]

    # Load employee-specific activities when both department and employee are selected
    if params[:department_id].present? && params[:employee_detail_id].present?
      begin
        # Get the department
        selected_department = Department.find(params[:department_id])

        # Get activities that have existing user_details for this specific employee
        # This ensures only activities relevant to the selected employee are shown
        @employee_activities = UserDetail.includes(:activity)
                                       .where(employee_detail_id: params[:employee_detail_id])
                                       .where.not(activity_id: nil)
                                       .map(&:activity)
                                       .uniq

        # If no existing activities found, show all department activities (for new entries)
        if @employee_activities.empty?
          @employee_activities = selected_department.activities
        end

        # FIXED: Only load user_details when BOTH department and employee are selected
        # This prevents showing all data when only one filter is applied
        @user_details = UserDetail.includes(:department, :activity, :employee_detail)
                                  .where(filter_conditions)
                                  .limit(100)
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
  end

  def create
    @user_detail = UserDetail.new(user_detail_params)

    if @user_detail.save
      redirect_to new_user_detail_path, notice: "User detail was successfully created."
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

      if @user_detail.update(user_detail_params)
        # Clear any existing flash messages
        flash.clear

        # Role-based redirect
        if current_user.hod?
          # HOD redirects to new user detail form
          redirect_to new_user_detail_path(department_id: department_id, employee_detail_id: employee_detail_id),
                      notice: "User detail was successfully updated."
        else
          # Employee/L1/L2 redirects to HOD TARGET FORM (index page)
          redirect_to user_details_path,
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
        redirect_to new_user_detail_path,
                    alert: "An error occurred while updating the user detail."
      else
        redirect_to user_details_path,
                    alert: "An error occurred while updating the user detail."
      end
    end
  end


  def update_quarterly_achievements
    # Get the correct parameters
    selected_quarter = params[:selected_quarter]
    achievement_data = params[:achievements] || {}
    success_count = 0
    errors = []
    updated_activities = []

    if achievement_data.empty?
      flash[:alert] = "No achievement data received. Please try again."
      redirect_to quarterly_edit_all_user_details_path
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
                                        .where(user_details: { employee_detail_id: employee_detail_id })
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

    redirect_to quarterly_edit_all_user_details_path

    rescue => e
      Rails.logger.error "Quarterly update error: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:alert] = "❌ An error occurred while updating achievements: #{e.message}"
      redirect_to quarterly_edit_all_user_details_path
  end

  # FIXED: Quarterly edit all method
  def quarterly_edit_all
    if current_user.role == "employee" || current_user.role == "l1_employer" || current_user.role == "l2_employer"
      employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)
      @user_details = if employee_detail
        UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
                .where(employee_detail_id: employee_detail.id)
                .order("departments.department_type, activities.activity_name")
      else
        UserDetail.none
      end
    elsif current_user.role == "hod"
      @user_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
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
          redirect_to new_user_detail_path(department_id: department_id, employee_detail_id: employee_detail_id),
                      notice: "User detail was successfully deleted."
        else
          # Employee/L1/L2 redirects to HOD TARGET FORM (index page)
          redirect_to user_details_path,
                      notice: "User detail was successfully deleted."
        end
      else
        # Clear any existing flash messages
        flash.clear

        # Role-based error redirect
        if current_user.hod?
          redirect_to new_user_detail_path,
                      alert: "Failed to delete user detail."
        else
          redirect_to user_details_path,
                      alert: "Failed to delete user detail."
        end
      end
    rescue ActiveRecord::RecordNotFound
      # Clear any existing flash messages
      flash.clear

      # Role-based error redirect
      if current_user.hod?
        redirect_to new_user_detail_path,
                    alert: "User detail not found."
      else
        redirect_to user_details_path,
                    alert: "User detail not found."
      end
    rescue => e
      Rails.logger.error "Error in destroy action: #{e.message}"

      # Clear any existing flash messages
      flash.clear

      # Role-based error redirect
      if current_user.hod?
        redirect_to new_user_detail_path,
                    alert: "An error occurred while deleting the user detail."
      else
        redirect_to user_details_path,
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
        redirect_to get_user_detail_user_details_path
        return
      end

      # Find the L1 manager
      l1_manager = EmployeeDetail.find_by("employee_code LIKE ?", test_employee.l1_code.strip + "%")

      if l1_manager.nil?
        flash[:alert] = "❌ L1 manager not found with code: #{test_employee.l1_code}"
        redirect_to get_user_detail_user_details_path
        return
      end

      if l1_manager.mobile_number.blank?
        flash[:alert] = "❌ L1 manager #{l1_manager.employee_name} has no mobile number"
        redirect_to get_user_detail_user_details_path
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

    redirect_to get_user_detail_user_details_path
  end

  def get_user_detail
    if [ "employee", "l1_employer", "l2_employer" ].include?(current_user.role)
      @employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if @employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
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

      # Deduplicate by keeping the most recent record for each activity-employee combination
      deduplicated_details = all_details.group_by { |detail| [ detail.activity_id, detail.employee_detail_id ] }.map do |key, records|
        records.max_by(&:updated_at)
      end

      # Convert to ActiveRecord relation and limit
      @user_details = UserDetail.where(id: deduplicated_details.map(&:id)).limit(100)
      @employee_detail = nil
    end
  end

  def submitted_achievements
    if [ "employee", "l1_employer", "l2_employer" ].include?(current_user.role)
      @employee_detail = EmployeeDetail.find_by(employee_email: current_user.email)

      @user_details = if @employee_detail
        # Get all user_details for this employee and deduplicate by activity
        all_details = UserDetail.includes(:department, :activity, :employee_detail, achievements: :achievement_remark)
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

                mark_sms_as_sent(employee_detail.id, quarter)
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
    user_details_params = params[:user_details]

    # Enhanced validation
    if department_id.blank?
      render json: { error: "Department ID is required" }, status: :bad_request
      return
    end

    if employee_detail_id.blank?
      render json: { error: "Employee Detail ID is required" }, status: :bad_request
      return
    end

    if user_details_params.blank?
      render json: { error: "No user details provided" }, status: :bad_request
      return
    end

    # Validate that department and employee exist
    unless Department.exists?(department_id)
      render json: { error: "Department not found" }, status: :not_found
      return
    end

    unless EmployeeDetail.exists?(employee_detail_id)
      render json: { error: "Employee not found" }, status: :not_found
      return
    end

    created_count = 0
    updated_count = 0
    errors = []

    # Bulk operations for better performance
    activity_ids = user_details_params.keys
    existing_records = UserDetail.where(
      department_id: department_id,
      activity_id: activity_ids,
      employee_detail_id: employee_detail_id
    ).index_by(&:activity_id)

    ActiveRecord::Base.transaction do
      user_details_params.each do |activity_id, details|
        begin
          unless Activity.exists?(activity_id)
            errors << "Activity with ID #{activity_id} not found"
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
            department_id: department_id,
            activity_id: activity_id,
            employee_detail_id: employee_detail_id
          )

          # Update Activity metadata (always update to handle clearing values)
          activity = Activity.find(activity_id)
          activity_update_data = {}

          # Always include unit and theme_name in update (nil values will clear the fields)
          activity_update_data[:unit] = activity_metadata[:unit]
          activity_update_data[:theme_name] = activity_metadata[:theme_name]

          unless activity.update(activity_update_data)
            errors << "Failed to update activity metadata for activity #{activity_id}: #{activity.errors.full_messages.join(', ')}"
          end

          # Update the user_detail record with monthly data
          user_detail_record.assign_attributes(month_data)

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

      response_data = {
        success: true,
        message: message.join(", "),
        created: created_count,
        updated: updated_count
      }

      response_data[:warnings] = errors if errors.present?

      render json: response_data
    else
      render json: {
        success: false,
        error: "Failed to save records",
        errors: errors,
        created: created_count,
        updated: updated_count
      }, status: :unprocessable_entity
    end
  end

  def export
    @user_details = UserDetail.includes(:employee_detail, :department, :activity)
                              .limit(5000)

    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = 'attachment; filename="user_details.xlsx"'
      }
    end
  end

  def import
    file = params[:file]

    unless file && [ ".xlsx", ".xls" ].include?(File.extname(file.original_filename))
      redirect_to new_user_detail_path, alert: "Please upload a valid .xlsx or .xls file."
      return
    end

    begin
      spreadsheet = Roo::Excelx.new(file.tempfile.path)
      header = spreadsheet.row(1)



      errors = []
      success_count = 0
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
            activity_theme_name = row["theme"] || row["activity_theme"]
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

            begin
              UserDetail.create!(
                employee_detail_id: employee.id,
                department_id: department.id,
                activity_id: activity.id,
                **months
              )
              success_count += 1
            rescue ActiveRecord::RecordInvalid => e
              errors << "Row #{i}: #{e.message}"
            end
          end
        end
      end

      if errors.any?
        if success_count > 0
          redirect_to new_user_detail_path, alert: "Partially imported: #{success_count} records saved, but #{errors.count} errors:\n#{errors.first(10).join("\n")}"
        else
          redirect_to new_user_detail_path, alert: "Import failed. Errors:\n#{errors.first(10).join("\n")}"
        end
      else
        redirect_to new_user_detail_path, notice: "Excel file imported successfully! #{success_count} records processed."
      end

    rescue => e
      Rails.logger.error "Import error: #{e.message}\n#{e.backtrace.join("\n")}"
      redirect_to new_user_detail_path, alert: "Error reading Excel file: #{e.message}"
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

  def user_detail_params
    params.require(:user_detail).permit(:department_id, :activity_id, :april, :may, :june,
                                        :july, :august, :september, :october, :november,
                                        :december, :january, :february, :march, :employee_detail_id, :employee_detail_email)
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
    @departments = Department.select(:id, :department_type)
    @activities = @user_detail.department_id.present? ?
                  Activity.select(:id, :activity_name, :unit, :theme_name)
                         .where(department_id: @user_detail.department_id) : []
    @user_details = UserDetail.includes(:department, :activity).limit(100)
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

  # SMS functionality for quarterly notifications
  def send_sms_to_l1(employee_detail, quarter, user_detail)
    begin
      # Get L1 manager's mobile number (not the employee's mobile number)
      l1_code = employee_detail.l1_code
      return { success: false, error: "L1 code not found for employee" } unless l1_code.present?

      # Find the L1 manager's employee detail record
      l1_manager = EmployeeDetail.find_by("employee_code LIKE ?", l1_code.strip + "%")
      return { success: false, error: "L1 manager not found with code: #{l1_code}" } unless l1_manager.present?

      l1_mobile = l1_manager.mobile_number
      return { success: false, error: "L1 manager mobile number not found" } unless l1_mobile.present?

      # Clean and validate mobile number
      l1_mobile = l1_mobile.to_s.strip.gsub(/\D/, "")
      return { success: false, error: "Invalid mobile number format" } if l1_mobile.length < 10

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
      response = HTTParty.get(api_url, query: params)


      if response.success?
        # Parse the JSON response to check if SMS was actually sent
        begin
          response_data = JSON.parse(response.body)
          if response_data["Status"] == "Success" && response_data["Code"] == "000"
            {
              success: true,
              message: "SMS sent successfully",
              message_id: response_data["Message-Id"],
              response: response_data
            }
          else
            Rails.logger.error "SMS API returned error: #{response_data}"
            {
              success: false,
              error: "SMS API error: #{response_data['Description'] || response_data['Status']}"
            }
          end
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse SMS API response: #{e.message}"
          { success: false, error: "Invalid SMS API response format" }
        end
      else
        Rails.logger.error "SMS API HTTP error: #{response.code} - #{response.body}"
        { success: false, error: "SMS API HTTP error: #{response.code}" }
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
    redirect_to get_user_detail_user_details_path
  end

  def view_sms_logs
    # View SMS logs to see which SMS have been sent
    @sms_logs = SmsLog.includes(:employee_detail).order(created_at: :desc).limit(50)
    render :view_sms_logs
  end

  def check_sms_already_sent(employee_detail_id, quarter)
    # Check if SMS was already sent for this quarter using database
    # Use employee_detail_id to track per employee, not per activity
    SmsLog.exists?(employee_detail_id: employee_detail_id, quarter: quarter, sent: true)
  end

  def mark_sms_as_sent(employee_detail_id, quarter)
    # Mark SMS as sent in database to prevent duplicates
    # Use employee_detail_id to track per employee, not per activity
    SmsLog.create!(
      employee_detail_id: employee_detail_id,
      quarter: quarter,
      sent: true,
      sent_at: Time.current
    )
  rescue => e
    Rails.logger.error "Failed to mark SMS as sent: #{e.message}"
  end
end
