require "roo"

class DepartmentsController < ApplicationController
  before_action :set_department, only: [ :show, :edit, :update, :destroy, :delete_user_activities, :delete_user_from_department ]
  before_action :load_employee_activities, only: [ :index, :export ]

  def index
    Rails.logger.info "Employee activities loaded successfully"

    @department = Department.new(financial_year: selected_financial_year)
    # Only build one activity by default to prevent duplicates
    @department.activities.build(financial_year: selected_financial_year)

    # Set variables needed for the form dropdowns
    @employee_departments = EmployeeDetail.distinct.pluck(:department).compact.reject(&:blank?)
    @employees = available_department_form_employees

    respond_to do |format|
      format.html
      format.json do
        render json: @employee_activities.values
      end
    end
  end

  def new
    @department = Department.new(financial_year: selected_financial_year)
    @employee_departments = EmployeeDetail.distinct.pluck(:department).compact.reject(&:blank?)
    @employees = available_department_form_employees
    # Only build one activity by default to prevent duplicates
    @department.activities.build(financial_year: selected_financial_year)
  end

  def create
    @department = Department.new(department_params_with_financial_year)

    if @department.save
      employee = find_employee_by_reference(@department.employee_reference)
      redirect_url = departments_path(financial_year: @department.financial_year, **employee_filter_params_for(employee))

      respond_to do |format|
        format.html { redirect_to redirect_url, notice: "Department was successfully created." }
        format.json { render json: { success: true, message: "Department created successfully!", financial_year: @department.financial_year, redirect_url: redirect_url } }
      end
    else
      respond_to do |format|
        format.html {
          @department.financial_year = requested_financial_year if @department.financial_year.blank?
          @department.activities.build(financial_year: @department.financial_year) if @department.activities.empty?
          @departments = Department.for_financial_year(requested_financial_year).includes(:activities)
          @employee_departments = EmployeeDetail.distinct.pluck(:department).compact.reject(&:blank?)
          @employees = available_department_form_employees
          load_employee_activities
          flash.now[:alert] = "Failed to create department: #{@department.errors.full_messages.join(', ')}"
          render :index, status: :unprocessable_entity
        }
        format.json { render json: { success: false, errors: @department.errors.full_messages } }
      end
    end
  end

  def edit
    @department = Department.find(params[:id])
    @employee_departments = EmployeeDetail.distinct.pluck(:department).compact
    @employees = available_department_form_employees
  end

  def edit_data
    # Disable caching to ensure fresh data is always returned
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    # The frontend is actually trying to edit employee activities, not departments
    # We need to find the employee and their activities based on the department ID

    # First try to find the department
    department = Department.find_by(id: params[:id], financial_year: selected_financial_year) || Department.find_by(id: params[:id])

    if department
      # If department exists, get its activities and employee info
      # But activities are actually linked through UserDetail records
      employee = find_employee_by_reference(department.employee_reference) ||
                 EmployeeDetail.find_by(department: department.department_type)

      if employee
        # FIXED: Get only activities that are specific to this employee
        # Instead of showing all department activities, show only user-specific activities

        # Get activities from UserDetail records for this specific employee
        user_details = UserDetail.includes(:activity, :department)
                                .assignment_consistent
                                .for_financial_year(selected_financial_year)
                                .where(employee_detail_id: employee.id)
                                .where.not(user_details: { activity_id: nil })

        # Map activities from user_details (employee-specific activities)
        activities = user_details.map do |user_detail|
          activity = user_detail.activity
          {
            id: activity.id,
            theme_name: user_detail.display_theme_name,
            activity_name: activity.activity_name,
            unit: user_detail.display_unit,
            weight: activity.weight
          }
        end.uniq { |activity| activity[:id] } # Remove duplicates

        employee_name = employee.employee_name
        employee_code = employee.employee_code

        render json: {
          id: department.id,
          department_type: department.department_type,
          theme_name: department.theme_name,
          employee_reference: employee_reference_for(employee),
          employee_name: employee_name,
          employee_code: employee_code,
          employee_display_name: employee ? "#{employee_name} (#{employee_code.presence || employee.employee_id})" : "N/A",
          financial_year: selected_financial_year,
          activities: activities,
          timestamp: Time.current.to_i
        }
      else
        # No employee found for this department
        render json: { error: "No employee found for this department" }, status: :not_found
      end
    else
      # If department doesn't exist, try to find employee activities by employee ID
      # This handles the case where the ID might actually be an employee ID
      employee = find_employee_by_reference(params[:id])

      if employee
        # Get activities for this employee using UserDetail
        user_details = UserDetail.includes(:activity, :department)
                                .assignment_consistent
                                .for_financial_year(selected_financial_year)
                                .where(employee_detail_id: employee.id)
                                .where.not(user_details: { activity_id: nil })

        activities = user_details.map do |user_detail|
          activity = user_detail.activity
          {
            id: activity.id,
            theme_name: user_detail.display_theme_name,
            activity_name: activity.activity_name,
            unit: user_detail.display_unit,
            weight: activity.weight
          }
        end

        # Find the department type from the first activity
        department_type = user_details.first&.department&.department_type || employee.department

        render json: {
          id: employee_reference_for(employee), # Use employee reference as the identifier
          department_type: department_type,
          theme_name: "", # No theme name for employee activities
          employee_reference: employee_reference_for(employee),
          employee_name: employee.employee_name,
          employee_code: employee.employee_code,
          employee_display_name: "#{employee.employee_name} (#{employee.employee_code || employee.employee_id})",
          financial_year: selected_financial_year,
          activities: activities,
          timestamp: Time.current.to_i
        }
      else
        # Neither department nor employee found
        render json: { error: "Department or employee not found" }, status: :not_found
      end
    end
  end

  # Handle employee-specific activity updates
  def handle_employee_activity_update(employee)
    Rails.logger.info "=== handle_employee_activity_update called for employee #{employee.employee_id} ==="

    if params[:department] && params[:department][:activities_attributes].present?
      Rails.logger.info "Processing employee activity updates for #{employee.employee_name}"

      begin
        ActiveRecord::Base.transaction do
          financial_year = requested_financial_year
          existing_user_details = UserDetail.assignment_consistent
                                           .where(employee_detail_id: employee.id, financial_year: financial_year)
          Rails.logger.info "Found #{existing_user_details.count} existing user_details for employee"

          department = existing_user_details.first&.department ||
                       Department.find_or_create_by!(
                         department_type: params.dig(:department, :department_type).presence || employee.department,
                         employee_reference: employee_reference_for(employee),
                         financial_year: financial_year
                       ) do |record|
                         record.theme_name = params.dig(:department, :theme_name)
                       end

          activities_to_remove_from_employee = []
          params[:department][:activities_attributes].each do |index, activity_attrs|
            if (activity_attrs[:_destroy] == "true" || activity_attrs[:_destroy] == true) && activity_attrs[:id].present? && activity_attrs[:id] != ""
              Rails.logger.info "Activity #{activity_attrs[:id]} marked for removal from employee #{employee.employee_id}"
              activities_to_remove_from_employee << activity_attrs[:id]
            end
          end

          activities_to_remove_from_employee.each do |activity_id|
            user_details_to_remove = existing_user_details.where(activity_id: activity_id)
            if user_details_to_remove.any?
              Rails.logger.info "Removing #{user_details_to_remove.count} user_details for activity #{activity_id} from employee #{employee.employee_id}"
              user_details_to_remove.destroy_all
            end

            activity = Activity.find_by(id: activity_id, financial_year: financial_year)
            activity&.destroy if activity.present? && !UserDetail.exists?(activity_id: activity.id, financial_year: financial_year)
          end

          params[:department][:activities_attributes].each do |index, activity_attrs|
            next if activity_attrs[:_destroy] == "true" || activity_attrs[:_destroy] == true
            next if activity_attrs[:theme_name].blank? || activity_attrs[:activity_name].blank? || activity_attrs[:weight].blank?

            activity_id = activity_attrs[:id]
            activity = if activity_id.present?
              Activity.find_by(id: activity_id, financial_year: financial_year) || Activity.find(activity_id)
            else
              department.activities.build(financial_year: financial_year)
            end

            activity.department = department
            activity.financial_year = financial_year

            if activity_id.present?
              Rails.logger.info "Updating activity #{activity_id} with new data"
            end

            activity.update!(
              theme_name: activity_attrs[:theme_name],
              activity_name: activity_attrs[:activity_name],
              unit: activity_attrs[:unit],
              weight: activity_attrs[:weight]
            )

            user_detail = UserDetail.find_or_initialize_by(
              employee_detail_id: employee.id,
              activity_id: activity.id,
              department_id: department.id,
              financial_year: financial_year
            )
            user_detail.theme_name = activity.theme_name
            user_detail.unit = activity.unit
            user_detail.save! if user_detail.new_record? || user_detail.changed?
          end

          Rails.logger.info "Successfully updated employee activities for #{employee.employee_name}"
          render json: {
            success: true,
            message: "Employee activities updated successfully!",
            financial_year: financial_year,
            redirect_url: departments_path(financial_year: financial_year, **employee_filter_params_for(employee))
          }
        end
      rescue => e
        Rails.logger.error "Error updating employee activities: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { success: false, message: "Error updating employee activities: #{e.message}" }, status: :unprocessable_entity
      end
    else
      Rails.logger.warn "No activities attributes found in params"
      render json: { success: false, message: "No activities data provided" }, status: :unprocessable_entity
    end
  end

  def update
    # Handle nested attributes with proper foreign key constraint handling
    begin
      ActiveRecord::Base.transaction do
        financial_year = @department.financial_year.presence || requested_financial_year
        # First, handle activities marked for destruction
        if department_params_with_financial_year[:activities_attributes].present?
          department_params_with_financial_year[:activities_attributes].each do |index, activity_attrs|
            if activity_attrs[:_destroy] == "true" && activity_attrs[:id].present?
              activity = Activity.find(activity_attrs[:id])

              # First delete dependent user_details records to avoid foreign key constraint violation
              user_details = UserDetail.where(activity_id: activity.id, financial_year: financial_year)
              if user_details.any?
                Rails.logger.info "Found #{user_details.count} user_details for activity #{activity.id}, deleting them first"
                user_details.destroy_all
              end

              # Now delete the activity
              activity.destroy
              Rails.logger.info "Successfully deleted activity #{activity.id}"
            end
          end
        end

    # Now update the department with the remaining activities
    if @department.update(department_params_with_financial_year)
      employee = find_employee_by_reference(@department.employee_reference)
      redirect_url = departments_path(financial_year: @department.financial_year, **employee_filter_params_for(employee))

      respond_to do |format|
        format.html { redirect_to redirect_url, notice: "Department was successfully updated." }
        format.json { render json: { success: true, message: "Department updated successfully!", financial_year: @department.financial_year, redirect_url: redirect_url } }
      end
    else
      respond_to do |format|
        format.html {
          @employee_departments = EmployeeDetail.distinct.pluck(:department).compact
          @employees = available_department_form_employees
          render :edit, status: :unprocessable_entity
        }
        format.json { render json: { success: false, errors: @department.errors.full_messages } }
          end
    end
      end
    rescue => e
      Rails.logger.error "Error updating department: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      respond_to do |format|
        format.html {
          @employee_departments = EmployeeDetail.distinct.pluck(:department).compact
          @employees = available_department_form_employees
          flash.now[:alert] = "Failed to update department: #{e.message}"
          render :edit, status: :unprocessable_entity
        }
        format.json { render json: { success: false, errors: [ e.message ] } }
      end
    end
  end

  def update_employee_activities
    Rails.logger.info "=== update_employee_activities method called ==="
    Rails.logger.info "Request method: #{request.method}"
    Rails.logger.info "Request path: #{request.path}"
    Rails.logger.info "Request headers: #{request.headers.to_h.select { |k, v| k.start_with?('HTTP_') }}"

    employee_id = params[:employee_id]

    Rails.logger.info "Updating activities for employee: #{employee_id}"
    Rails.logger.info "Received params: #{params.inspect}"

    # Find all departments for this employee
    departments = Department.where(employee_reference: employee_id, financial_year: requested_financial_year)
    Rails.logger.info "Found #{departments.count} departments for employee #{employee_id}"

    if departments.any?
      begin
        ActiveRecord::Base.transaction do
          # Update each department's activities
          departments.each do |dept|
            Rails.logger.info "Processing department #{dept.id} with #{dept.activities.count} existing activities"

                                      if params[:activities].present?
               Rails.logger.info "Processing #{params[:activities].count} activities for update"

               # Get existing activity IDs for this department
               existing_activity_ids = dept.activities.pluck(:id)
               Rails.logger.info "Existing activity IDs: #{existing_activity_ids}"

               # Find activities that are no longer in the form (deleted by user)
               # We'll need to check by content since the form doesn't send IDs for new activities
               activities_to_delete = []

               dept.activities.each do |existing_activity|
                 # Check if this activity still exists in the form data
                 activity_still_exists = params[:activities].any? do |form_activity|
                   form_activity[:theme_name] == existing_activity.theme_name &&
                   form_activity[:activity_name] == existing_activity.activity_name &&
                   form_activity[:unit] == existing_activity.unit &&
                   form_activity[:weight].to_s == existing_activity.weight.to_s
                 end

                 unless activity_still_exists
                   activities_to_delete << existing_activity
                   Rails.logger.info "Activity #{existing_activity.id} (#{existing_activity.activity_name}) will be deleted"
                 end
               end

               # Delete activities that are no longer in the form
               activities_to_delete.each do |activity|
                 Rails.logger.info "Deleting activity #{activity.id} (#{activity.activity_name})"

                 # First delete dependent user_details records to avoid foreign key constraint violation
                 user_details = UserDetail.where(activity_id: activity.id, financial_year: requested_financial_year)
                 if user_details.any?
                   Rails.logger.info "Found #{user_details.count} user_details for activity #{activity.id}, deleting them first"
                 user_details.destroy_all
                 end

                 # Now delete the activity
                 activity.destroy
                 Rails.logger.info "Successfully deleted activity #{activity.id}"
               end

               # Update or create activities
               params[:activities].each do |activity_params|
                 # Try to find existing activity by content
                 existing_activity = dept.activities.find_by(
                   theme_name: activity_params[:theme_name],
                   activity_name: activity_params[:activity_name],
                   unit: activity_params[:unit],
                   weight: activity_params[:weight]
                 )

                 if existing_activity
                   # Update existing activity
                   Rails.logger.info "Updating existing activity #{existing_activity.id}"
                   existing_activity.update!(
                     theme_name: activity_params[:theme_name],
                     activity_name: activity_params[:activity_name],
                     unit: activity_params[:unit],
                     weight: activity_params[:weight]
                   )
                 else
                   # Create new activity
                   Rails.logger.info "Creating new activity for department #{dept.id}"
                   new_activity = dept.activities.create!(
                     theme_name: activity_params[:theme_name],
                     activity_name: activity_params[:activity_name],
                     unit: activity_params[:unit],
                     weight: activity_params[:weight],
                     financial_year: requested_financial_year
                   )
                   Rails.logger.info "Created new activity #{new_activity.id}"
                 end
               end
                                      end
          end

          Rails.logger.info "Successfully updated activities for employee #{employee_id}"
          render json: { success: true, message: "Employee activities updated successfully!" }
        end
      rescue => e
        Rails.logger.error "Error updating employee activities: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { success: false, message: "Error updating activities: #{e.message}" }, status: :unprocessable_entity
      end
    else
      Rails.logger.warn "No departments found for employee #{employee_id}"
      render json: { success: false, message: "No departments found for this employee" }, status: :not_found
    end
  end

  # New action to handle updating employee activity data from the edit form
  def update_employee_activity_data
    # The ID could be either a department ID or employee ID
    id = params[:id]

    # First try to find the department
    department = Department.find_by(id: id, financial_year: requested_financial_year) || Department.find_by(id: id)

    # If not a department, try to find an employee
    if !department
      employee = find_employee_by_reference(id)
      if employee
        Rails.logger.info "Found employee: #{employee.employee_id} - #{employee.employee_name}"
        handle_employee_activity_update(employee)
        return
      end
    end

    if department
      # Update department activities using the nested attributes structure
      if params[:department] && params[:department][:activities_attributes].present?
        begin
          ActiveRecord::Base.transaction do
            # Get existing activity IDs for this department
            existing_activity_ids = department.activities.pluck(:id)

            # Count valid activities first (excluding those marked for destruction)
            valid_activities_count = 0
            activities_to_process = []

            params[:department][:activities_attributes].each do |index, activity_attrs|
              # Skip if marked for destruction
              next if activity_attrs[:_destroy] == "true" || activity_attrs[:_destroy] == true

              # Check if all required fields are present (unit is now optional)
              if activity_attrs[:theme_name].present? && activity_attrs[:activity_name].present? &&
                 activity_attrs[:weight].present?
                valid_activities_count += 1
                activities_to_process << index
              end
            end

            if valid_activities_count == 0
              raise "At least one complete activity is required. Please fill in all fields (Theme Name, Activity Name, and Weight) for at least one activity. Unit is optional."
            end

            # First, handle activities marked for destruction
            activities_to_delete = []
            params[:department][:activities_attributes].each do |index, activity_attrs|
              if (activity_attrs[:_destroy] == "true" || activity_attrs[:_destroy] == true) && activity_attrs[:id].present? && activity_attrs[:id] != ""
                activity = department.activities.find_by(id: activity_attrs[:id])
                if activity
                  activities_to_delete << activity
                end
              end
            end

            # Delete activities marked for destruction
            activities_to_delete.each do |activity|
              # First delete dependent user_details records to avoid foreign key constraint violation
              user_details = UserDetail.where(activity_id: activity.id, financial_year: requested_financial_year)
              if user_details.any?
                user_details.destroy_all
              end

              # Now delete the activity
              activity.destroy
            end

            # Process each activity from the form (only valid ones)
            params[:department][:activities_attributes].each do |index, activity_attrs|
              # Skip if marked for destruction
              if activity_attrs[:_destroy] == "true" || activity_attrs[:_destroy] == true
                next
              end

              # Skip if any required field is blank (incomplete activity) - unit is now optional
              if activity_attrs[:theme_name].blank? || activity_attrs[:activity_name].blank? ||
                 activity_attrs[:weight].blank?
                next
              end

              # Check if this is an existing activity (has an ID)
              if activity_attrs[:id].present? && activity_attrs[:id] != ""
                # Update existing activity
                existing_activity = department.activities.find_by(id: activity_attrs[:id])
                if existing_activity
                    existing_activity.update!(
                      theme_name: activity_attrs[:theme_name],
                      activity_name: activity_attrs[:activity_name],
                      unit: activity_attrs[:unit],
                      weight: activity_attrs[:weight],
                      financial_year: requested_financial_year
                    )

                  # Ensure UserDetail record exists for this activity
                  if department.employee_reference.present?
                    employee = find_employee_by_reference(department.employee_reference)
                    if employee
                    existing_user_detail = UserDetail.find_by(
                        department_id: department.id,
                        activity_id: existing_activity.id,
                        employee_detail_id: employee.id,
                        financial_year: requested_financial_year
                      )

                      unless existing_user_detail
                        UserDetail.create!(
                          department_id: department.id,
                          activity_id: existing_activity.id,
                          employee_detail_id: employee.id,
                          financial_year: requested_financial_year,
                          theme_name: existing_activity.theme_name,
                          unit: existing_activity.unit
                        )
                      end
                    end
                  end
                else
                  Rails.logger.warn "Activity with ID #{activity_attrs[:id]} not found, skipping"
                end
              else
                # Create new activity
                Rails.logger.info "Creating new activity for department #{department.id}"
                new_activity = department.activities.create!(
                  theme_name: activity_attrs[:theme_name],
                  activity_name: activity_attrs[:activity_name],
                  unit: activity_attrs[:unit],
                  weight: activity_attrs[:weight],
                  financial_year: requested_financial_year
                )
                Rails.logger.info "Created new activity #{new_activity.id}"

                # Create UserDetail record to link activity to employee
                if department.employee_reference.present?
                  employee = find_employee_by_reference(department.employee_reference)
                  if employee
                    user_detail = UserDetail.find_or_initialize_by(
                      department_id: department.id,
                      activity_id: new_activity.id,
                      employee_detail_id: employee.id,
                      financial_year: requested_financial_year
                    )
                    user_detail.theme_name = new_activity.theme_name
                    user_detail.unit = new_activity.unit
                    user_detail.save! if user_detail.new_record? || user_detail.changed?
                    Rails.logger.info "Created UserDetail linking activity #{new_activity.id} to employee #{employee.employee_id}"
                  end
                end
              end
            end

            # Find activities that are no longer in the form and delete them
            form_activity_ids = params[:department][:activities_attributes].values
              .select { |attrs| attrs[:id].present? && attrs[:id] != "" && attrs[:_destroy] != "true" && attrs[:_destroy] != true }
              .map { |attrs| attrs[:id].to_i }

            Rails.logger.info "Form activity IDs (not marked for destruction): #{form_activity_ids}"
            Rails.logger.info "Current department activities: #{department.activities.pluck(:id)}"

            activities_to_delete = department.activities.where.not(id: form_activity_ids)

            if activities_to_delete.any?
              Rails.logger.info "Found #{activities_to_delete.count} activities to delete that are no longer in form"
              activities_to_delete.each do |activity|
                Rails.logger.info "Deleting activity #{activity.id} (#{activity.activity_name}) - no longer in form"

                # First delete dependent user_details records to avoid foreign key constraint violation
                user_details = UserDetail.where(activity_id: activity.id, financial_year: requested_financial_year)
                if user_details.any?
                  Rails.logger.info "Found #{user_details.count} user_details for activity #{activity.id}, deleting them first"
                  user_details.destroy_all
                end

                # Now delete the activity
                if activity.destroy
                  Rails.logger.info "Successfully deleted activity #{activity.id} that was no longer in form"
                else
                  Rails.logger.error "Failed to delete activity #{activity.id}: #{activity.errors.full_messages.join(', ')}"
                end
              end
            else
              Rails.logger.info "No activities to delete that are no longer in form"
            end
          end

          Rails.logger.info "Successfully updated department activities"
          render json: { success: true, message: "Department activities updated successfully!", financial_year: requested_financial_year }
        rescue => e
          Rails.logger.error "Error updating department activities: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: { success: false, message: "Error updating activities: #{e.message}" }, status: :unprocessable_entity
        end
      else
        Rails.logger.warn "No activities provided in params"
        Rails.logger.warn "params[:department]: #{params[:department].inspect}"
        Rails.logger.warn "params[:department][:activities_attributes]: #{params[:department]&.dig(:activities_attributes).inspect}"
        Rails.logger.warn "All params keys: #{params.keys.inspect}"
        Rails.logger.warn "Form data structure: #{params.inspect}"
        render json: { success: false, message: "No activities provided. Please check the form data structure." }, status: :unprocessable_entity
      end
    else
      # Try to find employee by ID
      employee = find_employee_by_reference(id)

      if employee
        # This would require a different approach since we're dealing with UserDetail records
        # For now, return an error suggesting to use the regular update method
        render json: { success: false, message: "Employee activities should be updated through the regular update method" }, status: :unprocessable_entity
      else
        render json: { success: false, message: "Department or employee not found" }, status: :not_found
      end
    end
  end

  def import
    file = params[:file]
    selected_year = requested_financial_year

    if file.nil?
      redirect_to departments_path(financial_year: selected_year), alert: "Please upload a file."
      return
    end

    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1)

    header_map = {
      "Department" => "department_type",
      "Employee Name" => "employee_name",
      "Financial Year" => "financial_year",
      "Theme Name" => "theme_name",
      "Activity Name" => "activity_name",
      "Unit" => "unit",
      "Weight" => "weight"
    }

    departments_hash = {}
    import_errors = []
    success_count = 0

    (2..spreadsheet.last_row).each do |i|
      row_data = spreadsheet.row(i)
      row = Hash[[ header, row_data ].transpose]
      mapped = row.transform_keys { |key| header_map[key] }.compact

      # Skip empty rows
      next if mapped["department_type"].blank? && mapped["employee_name"].blank? && mapped["theme_name"].blank?

      # Validate required fields
      if mapped["department_type"].blank?
        import_errors << "Row #{i}: Department is required"
        next
      end

      if mapped["employee_name"].blank?
        import_errors << "Row #{i}: Employee Name is required"
        next
      end

      if mapped["theme_name"].blank?
        import_errors << "Row #{i}: Theme Name is required"
        next
      end

      # Find employee reference by employee name
      employee = EmployeeDetail.find_by(employee_name: mapped["employee_name"])
      if employee.nil?
        import_errors << "Row #{i}: Employee '#{mapped["employee_name"]}' not found in system"
        next
      end

      row_financial_year = UserDetail.normalize_financial_year(mapped["financial_year"]).presence || selected_year

      # Create unique key for each department-employee-theme-year combination
      employee_reference = employee_reference_for(employee)
      key = "#{mapped["department_type"]}-#{employee_reference}-#{mapped["theme_name"]}-#{row_financial_year}"
      departments_hash[key] ||= {
        department_type: mapped["department_type"],
        employee_reference: employee_reference,
        financial_year: row_financial_year,
        theme_name: mapped["theme_name"],
        activities: []
      }

      # Only add activity if activity data is present
      if mapped["activity_name"].present?
        departments_hash[key][:activities] << {
          theme_name: mapped["theme_name"],
          activity_name: mapped["activity_name"],
          unit: mapped["unit"],
          weight: mapped["weight"]
        }
      end
    end

    if import_errors.any?
      redirect_to departments_path(financial_year: selected_year), alert: "❌ Import failed: #{import_errors.join(', ')}"
      return
    end

    # Create departments and activities
    ActiveRecord::Base.transaction do
      departments_hash.each_value do |dept_data|
        department = Department.find_or_initialize_by(
          department_type: dept_data[:department_type],
          employee_reference: dept_data[:employee_reference],
          theme_name: dept_data[:theme_name],
          financial_year: dept_data[:financial_year]
        )
        department.save!

        employee = find_employee_by_reference(dept_data[:employee_reference])

        dept_data[:activities].each do |act|
          activity = department.activities.find_or_initialize_by(
            theme_name: act[:theme_name],
            activity_name: act[:activity_name],
            unit: act[:unit],
            weight: act[:weight],
            financial_year: dept_data[:financial_year]
          )
          activity.save!

          next unless employee

          user_detail = UserDetail.find_or_initialize_by(
            department_id: department.id,
            activity_id: activity.id,
            employee_detail_id: employee.id,
            financial_year: dept_data[:financial_year]
          )
          user_detail.theme_name = activity.theme_name
          user_detail.unit = activity.unit
          user_detail.save! if user_detail.new_record? || user_detail.changed?
        end

        success_count += 1
      end
    end

    redirect_to departments_path(financial_year: selected_year), notice: "✅ Successfully imported #{success_count} department(s) with activities for #{selected_year}!"
  rescue => e
    redirect_to departments_path(financial_year: selected_year), alert: "❌ Import failed: #{e.message}"
  end

  def export
    @selected_financial_year = selected_financial_year
    @employee_activities = @employee_activities.presence || get_all_employee_activities

    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=\"departments_export_#{selected_financial_year.tr('-', '_')}.xlsx\""
        render xlsx: "export", template: "departments/export"
      }
    end
  end

  def destroy
    begin
      # Check if this is a request to delete a specific user's activities
      if params[:user_id].present?
        # Delete only specific user's activities from this department
        delete_user_activities_from_department(params[:user_id])
        message = "User activities deleted successfully from this department."
      else
        # Delete the entire department (existing behavior)
        ActiveRecord::Base.transaction do
          # First, delete all records that reference activities in this department
          @department.activities.each do |activity|
            # Delete user_details that reference this activity
            user_details = UserDetail.where(activity_id: activity.id, financial_year: selected_financial_year)
            user_details.destroy_all
          end

          # Now delete the activities
          @department.activities.for_financial_year(selected_financial_year).destroy_all

          # Finally delete the department
          @department.destroy if @department.financial_year == selected_financial_year || @department.financial_year.blank?
        end
        message = "Department was successfully deleted."
      end

      respond_to do |format|
        format.html { redirect_to departments_path(financial_year: selected_financial_year), notice: message }
        format.json { render json: { success: true, message: message, financial_year: selected_financial_year } }
      end
    rescue => e
      Rails.logger.error "Error deleting department: #{e.message}"
      respond_to do |format|
        format.html { redirect_to departments_path(financial_year: selected_financial_year), alert: "Error deleting department: #{e.message}" }
        format.json { render json: { success: false, message: "Error deleting department: #{e.message}" }, status: :unprocessable_entity }
      end
    end
  end

  # New method to delete specific user's activities from a department
  def delete_user_activities_from_department(user_id)
    Rails.logger.info "=== delete_user_activities_from_department method called ==="
    Rails.logger.info "Deleting activities for user: #{user_id} from department: #{@department.id}"

    begin
      ActiveRecord::Base.transaction do
        # Find the employee detail for this user
        employee_detail = find_employee_by_reference(user_id)

        if employee_detail
          Rails.logger.info "Found employee: #{employee_detail.employee_name}"

          # Find all user_details for this specific employee in this department
          user_details = UserDetail.where(
            department_id: @department.id,
            employee_detail_id: employee_detail.id,
            financial_year: selected_financial_year
          )

          user_details_count = user_details.count
          Rails.logger.info "Found #{user_details_count} user_details for employee #{employee_detail.employee_name} in department #{@department.id}"

          if user_details_count > 0
            # Delete the user_details (achievements and achievement_remarks will be deleted automatically due to dependent: :destroy)
            user_details.destroy_all
            Rails.logger.info "Deleted #{user_details_count} user_details for employee #{employee_detail.employee_name}"

            # Check if this was the only employee in this department
            remaining_user_details = UserDetail.where(department_id: @department.id, financial_year: selected_financial_year)

            if remaining_user_details.count == 0
              Rails.logger.info "No more user_details in department #{@department.id}, deleting department and activities"
              # If no more user_details, delete the department and activities
              @department.activities.for_financial_year(selected_financial_year).destroy_all
              @department.destroy if @department.financial_year == selected_financial_year || @department.financial_year.blank?
            else
              Rails.logger.info "Department #{@department.id} still has #{remaining_user_details.count} other user_details, keeping department"
            end
          else
            Rails.logger.info "No user_details found for employee #{employee_detail.employee_name} in department #{@department.id}"
          end
        else
          Rails.logger.error "Employee detail not found for user_id: #{user_id}"
          raise "Employee not found"
        end
      end
    rescue => e
      Rails.logger.error "Error deleting user activities: #{e.message}"
      raise e
    end
  end

  # New method to handle the delete_user_activities route
  def delete_user_activities
    # Handle both form data and JSON parameters
    user_id = params[:employee_id] || params[:user_id]

    if user_id.blank?
      respond_to do |format|
        format.html { redirect_to departments_path, alert: "Employee ID is required" }
        format.json { render json: { success: false, message: "Employee ID is required" }, status: :bad_request }
      end
      return
    end

    Rails.logger.info "delete_user_activities called with user_id: #{user_id}"

    begin
      delete_user_activities_from_department(user_id)

      respond_to do |format|
        format.html { redirect_to departments_path(financial_year: selected_financial_year), notice: "User activities deleted successfully from this department!" }
        format.json { render json: { success: true, message: "User activities deleted successfully from this department!" } }
      end
    rescue => e
      Rails.logger.error "Error in delete_user_activities: #{e.message}"

      respond_to do |format|
        format.html { redirect_to departments_path(financial_year: selected_financial_year), alert: "Error deleting user activities: #{e.message}" }
        format.json { render json: { success: false, message: "Error deleting user activities: #{e.message}" }, status: :unprocessable_entity }
      end
    end
  end

  # New method to handle the delete_user_from_department route
  def delete_user_from_department
    user_id = params[:user_id] || params[:employee_id]

    if user_id.blank?
      render json: { success: false, message: "User ID is required" }, status: :bad_request
      return
    end

    begin
      delete_user_activities_from_department(user_id)
      render json: { success: true, message: "User deleted successfully from this department!" }
    rescue => e
      Rails.logger.error "Error in delete_user_from_department: #{e.message}"
      render json: { success: false, message: "Error deleting user from department: #{e.message}" }, status: :unprocessable_entity
    end
  end

  def delete_employee_activities
    employee_id = params[:employee_id]

    Rails.logger.info "=== delete_employee_activities method called ==="
    Rails.logger.info "Deleting activities for employee: #{employee_id}"

    # Find all departments for this employee
    departments = Department.where(employee_reference: employee_id, financial_year: selected_financial_year)
    Rails.logger.info "Found #{departments.count} departments for employee #{employee_id}"

    if departments.any?
      begin
        # Delete all activities and departments for this employee
        ActiveRecord::Base.transaction do
          departments.each do |dept|
            Rails.logger.info "Processing department #{dept.id} with #{dept.activities.count} activities"

           # First, delete all records that reference these activities
           dept.activities.each do |activity|
             Rails.logger.info "Deleting references for activity #{activity.id}"

             # Delete user_details that reference this activity
             # This will automatically delete associated achievements and achievement_remarks due to dependent: :destroy
             user_details = UserDetail.where(activity_id: activity.id, financial_year: selected_financial_year)
             user_details_count = user_details.count
             Rails.logger.info "Found #{user_details_count} user_details for activity #{activity.id}"

             # Delete the user_details (achievements and achievement_remarks will be deleted automatically)
             user_details.destroy_all
             Rails.logger.info "Deleted #{user_details_count} user_details for activity #{activity.id}"
           end

            # Now delete the activities
            activities_count = dept.activities.count
            dept.activities.destroy_all
            Rails.logger.info "Deleted #{activities_count} activities from department #{dept.id}"

            # Finally delete the department
            dept.destroy
            Rails.logger.info "Deleted department #{dept.id}"
          end
        end

        render json: { success: true, message: "Employee activities deleted successfully!" }
      rescue => e
        Rails.logger.error "Error deleting employee activities: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
        render json: { success: false, message: "Error deleting activities: #{e.message}" }, status: :unprocessable_entity
      end
    else
      render json: { success: false, message: "No activities found for this employee" }
    end
  end

  def test_route
    Rails.logger.info "=== test_route method called ==="
    render json: { success: true, message: "Test route working!" }
  end

  def delete_activity
    activity_id = params[:activity_id]

    Rails.logger.info "=== delete_activity method called ==="
    Rails.logger.info "Deleting activity: #{activity_id}"

    begin
      activity = Activity.find(activity_id)

             ActiveRecord::Base.transaction do
         # First, delete all records that reference this activity
         user_details = UserDetail.where(activity_id: activity_id, financial_year: selected_financial_year)
         user_details_count = user_details.count
         Rails.logger.info "Found #{user_details_count} user_details for activity #{activity_id}"

         # Delete the user_details (achievements and achievement_remarks will be deleted automatically due to dependent: :destroy)
         user_details.destroy_all
         Rails.logger.info "Deleted #{user_details_count} user_details for activity #{activity_id}"

         # Now delete the activity
         activity.destroy
         Rails.logger.info "Deleted activity #{activity_id}"
       end

      render json: { success: true, message: "Activity deleted successfully!" }
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, message: "Activity not found" }, status: :not_found
    rescue => e
      Rails.logger.error "Error deleting activity: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      render json: { success: false, message: "Error deleting activity: #{e.message}" }, status: :unprocessable_entity
    end
  end

  # Debug method to show current data structure
  def debug_data
    @departments = Department.includes(:activities).all
    @employee_details = EmployeeDetail.all

    render json: {
      departments: @departments.map do |dept|
        {
          id: dept.id,
          department_type: dept.department_type,
          theme_name: dept.theme_name,
          employee_reference: dept.employee_reference,
          employee_name: dept.employee_name,
          activities_count: dept.activities.count,
          activities: dept.activities.map do |act|
            {
              id: act.id,
              theme_name: act.theme_name,
              activity_name: act.activity_name,
              unit: act.unit,
              weight: act.weight
            }
          end
        }
      end,
      employee_details: @employee_details.map do |emp|
        {
          id: emp.id,
          employee_id: emp.employee_id,
          employee_name: emp.employee_name,
          employee_code: emp.employee_code,
          department: emp.department
        }
      end
    }
  end

  private

  def set_department
    @department = Department.find_by(id: params[:id], financial_year: requested_financial_year) || Department.find(params[:id])
  end

  def department_params
    params.require(:department).permit(:department_type, :employee_reference, :theme_name, :financial_year,
    activities_attributes: [ :id, :theme_name, :activity_name, :unit, :weight, :_destroy, :financial_year ])
  end

  def department_params_with_financial_year
    attributes = department_params.to_h.deep_dup
    financial_year = requested_financial_year

    attributes["financial_year"] = financial_year
    attributes["activities_attributes"]&.each_value do |activity_attrs|
      activity_attrs["financial_year"] = financial_year
    end

    attributes.deep_symbolize_keys
  end

  def requested_financial_year
    UserDetail.normalize_financial_year(params[:financial_year] || params.dig(:department, :financial_year)).presence || selected_financial_year
  end

  def load_employee_activities
    if params[:employee_id].present?
      @selected_employee = find_employee_by_reference(params[:employee_id])
      @employee_activities = @selected_employee ? get_employee_activities(@selected_employee) : {}
    elsif params[:employee_code].present?
      @selected_employee = find_employee_by_reference(params[:employee_code])
      @employee_activities = @selected_employee ? get_employee_activities(@selected_employee) : {}
    else
      @selected_employee = nil
      @employee_activities = get_all_employee_activities
    end
  end

  # Get activities for a specific employee using UserDetail
  def get_employee_activities(employee)
    activities_hash = {}

    # Get all user_details for this employee and deduplicate
    user_details = UserDetail.includes(:activity, :department)
                            .assignment_consistent
                            .for_financial_year(selected_financial_year)
                            .where(employee_detail_id: employee.id)
                            .where.not(user_details: { activity_id: nil })

    # Deduplicate by keeping the most recent record for each activity
    deduplicated_details = user_details.group_by(&:activity_id).map do |activity_id, records|
      records.max_by(&:updated_at)
    end

    deduplicated_details.each do |user_detail|
      activity = user_detail.activity
      department = user_detail.department

      # Group by employee ONLY - no department grouping
      employee_reference = employee_reference_for(employee)
      key = employee_reference.to_s

      activities_hash[key] ||= {
        id: department.id, # Use department.id for Edit functionality
        employee_id: employee_reference,
        employee_name: employee.employee_name,
        employee_code: employee.employee_code,
        department: employee.department, # Employee's department
        department_type: department.department_type, # Activity's department
        financial_year: user_detail.financial_year,
        total_activities: 0,
        activities: []
      }

      activities_hash[key][:activities] << {
        id: activity.id,
        theme_name: user_detail.display_theme_name,
        activity_name: activity.activity_name,
        unit: user_detail.display_unit,
        weight: activity.weight,
        department_type: department.department_type
      }
      activities_hash[key][:total_activities] += 1
    end

    activities_hash
  end

  # Get all employees with their activities grouped by employee
  def get_all_employee_activities
    activities_hash = {}

    # Get all employees who have user_details
    employees_with_activities = EmployeeDetail.joins(:user_details)
                                             .merge(UserDetail.assignment_consistent.for_financial_year(selected_financial_year))
                                             .distinct
                                             .includes(:user_details)

    employees_with_activities.each do |employee|
      # Get activities for this employee and deduplicate
      user_details = UserDetail.includes(:activity, :department)
                              .assignment_consistent
                              .for_financial_year(selected_financial_year)
                              .where(employee_detail_id: employee.id)
                              .where.not(user_details: { activity_id: nil })

      # Deduplicate by keeping the most recent record for each activity
      deduplicated_details = user_details.group_by(&:activity_id).map do |activity_id, records|
        records.max_by(&:updated_at)
      end

      deduplicated_details.each do |user_detail|
        activity = user_detail.activity
        department = user_detail.department

        # Group by employee ONLY - no department grouping
        employee_reference = employee_reference_for(employee)
        key = employee_reference.to_s

        activities_hash[key] ||= {
          id: department.id, # Use department.id for Edit functionality
          employee_id: employee_reference,
          employee_name: employee.employee_name,
          employee_code: employee.employee_code,
          department: employee.department, # Employee's department
          department_type: department.department_type, # Activity's department
          financial_year: user_detail.financial_year,
          total_activities: 0,
          activities: []
        }

        activities_hash[key][:activities] << {
          id: activity.id,
          theme_name: user_detail.display_theme_name,
          activity_name: activity.activity_name,
          unit: user_detail.display_unit,
          weight: activity.weight,
          department_type: department.department_type
        }
        activities_hash[key][:total_activities] += 1
      end
    end

    # Sort by employee name
    activities_hash.sort_by { |key, data| data[:employee_name] }.to_h
  end

  def available_department_form_employees
    EmployeeDetail.where.not(employee_name: [ nil, "" ])
                  .where("employee_id IS NOT NULL OR employee_code IS NOT NULL")
                  .order(:employee_name)
  end

  def find_employee_by_reference(reference)
    return if reference.blank?

    EmployeeDetail.find_by(employee_id: reference) || EmployeeDetail.find_by(employee_code: reference)
  end

  def employee_reference_for(employee)
    employee&.employee_id.presence || employee&.employee_code
  end

  def employee_filter_params_for(employee)
    return {} unless employee

    if employee.employee_id.present?
      { employee_id: employee.employee_id }
    elsif employee.employee_code.present?
      { employee_code: employee.employee_code }
    else
      {}
    end
  end
end
