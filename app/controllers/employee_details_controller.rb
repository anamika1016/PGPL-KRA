require "roo"
require "axlsx"

class EmployeeDetailsController < ApplicationController
  before_action :set_employee_detail, only: [ :edit, :update, :destroy ]
  load_and_authorize_resource except: [ :approve, :return, :l2_approve, :l2_return, :edit_l1, :edit_l2 ]

  def index
    @employee_detail = EmployeeDetail.new
    @q = EmployeeDetail.ransack(params[:q])
    @employee_details = @q.result.order(created_at: :desc).page(params[:page]).per(10)
  end

  def create
    @employee_detail = EmployeeDetail.new(employee_detail_params)
    @employee_detail.user = current_user

    @q = EmployeeDetail.ransack(params[:q])
    if @employee_detail.save
      redirect_to employee_details_path, notice: "Employee created successfully."
    else
      @employee_details = @q.result.order(created_at: :desc).page(params[:page]).per(10)
      flash.now[:alert] = "Failed to create employee."
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @employee_detail.update(employee_detail_params)
      redirect_to employee_details_path, notice: "Employee updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    begin
      @employee_detail.destroy

      # Check if the request came from L2 view and redirect appropriately
      if request.referer&.include?("/employee_details/l2")
        redirect_to l2_employee_details_path, notice: "Employee deleted successfully."
      else
        redirect_to employee_details_path, notice: "Employee deleted successfully."
      end
    rescue => e
      Rails.logger.error "Error deleting employee detail: #{e.message}"

      # Check if the request came from L2 view and redirect appropriately
      if request.referer&.include?("/employee_details/l2")
        redirect_to l2_employee_details_path, alert: "Failed to delete employee. Please try again."
      else
        redirect_to employee_details_path, alert: "Failed to delete employee. Please try again."
      end
    end
  end

  def export_xlsx
    @employee_details = EmployeeDetail.all

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Employees") do |sheet|
      sheet.add_row [
        "Name", "Email", "Employee Code",
        "L1 Code", "L2 Code", "L1 Name", "L2 Name", "Post", "Department"
      ]

      @employee_details.each do |emp|
        sheet.add_row [
          emp.employee_name,
          emp.employee_email,
          emp.employee_code,
          emp.l1_code,
          emp.l2_code,
          emp.l1_employer_name,
          emp.l2_employer_name,
          emp.post,
          emp.department
        ]
      end
    end

    tempfile = Tempfile.new([ "employee_details", ".xlsx" ])
    package.serialize(tempfile.path)
    send_file tempfile.path, filename: "employee_details.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def export_quarterly_xlsx
    requested_financial_year = selected_financial_year
    @employee_details = EmployeeDetail.includes(user_details: [ :activity, :department, { achievements: :achievement_remark } ]).all

    package = Axlsx::Package.new
    workbook = package.workbook

    worksheet_name = "Quarterly L1 L2 #{requested_financial_year}".truncate(31)

    workbook.add_worksheet(name: worksheet_name) do |sheet|
      # Add header row
      sheet.add_row [
        "Employee Name", "Employee Code", "Department", "Quarter End Month",
        "L1 Name", "L1 Employee Code", "L1 Remarks", "L1 Percentage",
        "L2 Name", "L2 Employee Code", "L2 Remarks", "L2 Percentage"
      ]

      # Define quarters - Fixed sequence as per requirement with display names
      quarters = {
        "Q1" => { months: [ "april", "may", "june" ], display: "Apr-Jun" },
        "Q2" => { months: [ "july", "august", "september" ], display: "Jul-Sep" },
        "Q3" => { months: [ "october", "november", "december" ], display: "Oct-Dec" },
        "Q4" => { months: [ "january", "february", "march" ], display: "Jan-Mar" }
      }

      # Process each employee and quarter
      @employee_details.each do |emp|
        yearly_user_details = financial_year_user_details_for(emp)
        next if yearly_user_details.blank?

        quarters.each do |quarter_name, quarter_data|
          quarter_months = quarter_data[:months]
          quarter_display = quarter_data[:display]

          # Get all achievements for this employee in this quarter
          all_quarter_achievements = yearly_user_details.flat_map(&:achievements).select { |ach| quarter_months.include?(ach.month) }

          # Only add row if there are achievements in this quarter
          if all_quarter_achievements.any?
            # Get L1 and L2 data from achievement remarks
            l1_remarks = []
            l1_percentages = []
            l2_remarks = []
            l2_percentages = []

            all_quarter_achievements.each do |achievement|
              if achievement.achievement_remark.present?
                if achievement.achievement_remark.l1_remarks.present?
                  l1_remarks << achievement.achievement_remark.l1_remarks
                end
                if achievement.achievement_remark.l1_percentage.present?
                  l1_percentages << achievement.achievement_remark.l1_percentage.to_f
                end
                if achievement.achievement_remark.l2_remarks.present?
                  l2_remarks << achievement.achievement_remark.l2_remarks
                end
                if achievement.achievement_remark.l2_percentage.present?
                  l2_percentages << achievement.achievement_remark.l2_percentage.to_f
                end
              end
            end

            # Calculate averages
            l1_avg = l1_percentages.any? ? (l1_percentages.sum / l1_percentages.size).round(1) : 0.0
            l2_avg = l2_percentages.any? ? (l2_percentages.sum / l2_percentages.size).round(1) : 0.0

            # Join remarks with semicolons
            l1_remarks_text = l1_remarks.uniq.join("; ")
            l2_remarks_text = l2_remarks.uniq.join("; ")

            sheet.add_row [
              emp.employee_name || "N/A",
              emp.employee_code || "N/A",
              emp.department || "N/A",
              quarter_display,
              emp.l1_employer_name || "N/A",
              emp.l1_code || "N/A",
              l1_remarks_text.presence || "N/A",
              l1_avg > 0 ? "#{l1_avg}%" : "N/A",
              emp.l2_employer_name || "N/A",
              emp.l2_code || "N/A",
              l2_remarks_text.presence || "N/A",
              l2_avg > 0 ? "#{l2_avg}%" : "N/A"
            ]
          end
        end
      end
    end

    tempfile = Tempfile.new([ "quarterly_l1_l2_data", ".xlsx" ])
    package.serialize(tempfile.path)
    send_file tempfile.path,
              filename: "quarterly_l1_l2_data_#{requested_financial_year.tr('-', '_')}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import
    file = params[:file]

    if file.nil?
      redirect_to employee_details_path, alert: "Please upload a file."
      return
    end

    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1).map { |value| normalize_import_header(value) }

    header_map = {
      "employeeid" => "employee_id",
      "name" => "employee_name",
      "employeename" => "employee_name",
      "email" => "employee_email",
      "employeeemail" => "employee_email",
      "employeecode" => "employee_code",
      "empcode" => "employee_code",
      "mobile" => "mobile_number",
      "mobilenumber" => "mobile_number",
      "mobile no" => "mobile_number",
      "mobileno" => "mobile_number",
      "mobile#" => "mobile_number",
      "l1code" => "l1_code",
      "l2code" => "l2_code",
      "l1name" => "l1_employer_name",
      "l1employername" => "l1_employer_name",
      "l2name" => "l2_employer_name",
      "l2employername" => "l2_employer_name",
      "post" => "post",
      "department" => "department"
    }

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[ header, spreadsheet.row(i) ].transpose]
      mapped_row = row.each_with_object({}) do |(key, value), mapped|
        attribute_name = header_map[key.to_s]
        next unless attribute_name
        next if value.nil?

        cleaned_value = value.is_a?(String) ? value.strip : value
        next if cleaned_value.respond_to?(:blank?) ? cleaned_value.blank? : cleaned_value.nil?

        mapped[attribute_name] = cleaned_value
      end

      begin
        next if mapped_row.empty?

        employee_detail = find_existing_employee_detail(mapped_row) || EmployeeDetail.new
        employee_detail.assign_attributes(mapped_row)
        employee_detail.save!
      rescue => e
        puts "Import failed for row #{i}: #{e.message}"
        next
      end
    end

    redirect_to employee_details_path, notice: "✅ Employees imported successfully!"
  end

  # L1 Dashboard - Show quarterly data
  def l1
    authorize! :l1, EmployeeDetail

    if current_user.hod?
      # PERFORMANCE FIX: Optimize includes to preload all necessary associations
      @employee_details = EmployeeDetail.includes(
        user_details: [
          :activity,
          :department,
          achievements: :achievement_remark
        ]
      ).all
    else
      # PERFORMANCE FIX: Optimize includes to preload all necessary associations
      @employee_details = EmployeeDetail
                            .where(status: [ "pending", "l1_returned", "l1_approved", "l2_returned", "l2_approved" ])
                            .where(l1_code: current_user.employee_code)
                            .includes(
                              user_details: [
                                :activity,
                                :department,
                                achievements: :achievement_remark
                              ]
                            )
    end

    # Group employees by quarters for display
    @quarterly_data = group_employees_by_quarters(@employee_details)

    # Create the data structure expected by the view
    @quarterly_employee_data = build_quarterly_employee_data(@employee_details)

    # PERFORMANCE FIX: Pre-calculate summary data to avoid processing in view
    @summary_data = calculate_summary_data(@employee_details)
  end

  # Show employee details with quarterly view
  def show
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      return
    end

    authorize! :read, @employee_detail

    @user_detail_id = params[:user_detail_id]
    @selected_quarter = params[:quarter]

    # FIXED: Get ALL user details, not just those with achievements
    @user_details = financial_year_user_details_for(@employee_detail)
                      .includes(:activity, :department, achievements: :achievement_remark)

    # If quarter is selected, filter achievements by quarter
    if @selected_quarter.present?
      @quarterly_activities = get_quarterly_activities(@user_details, @selected_quarter)
    else
      @quarterly_activities = get_all_quarterly_activities(@user_details)
    end

    @can_approve_or_return = can_act_as_l1?(@employee_detail)
  end

  # Quarterly approval - approve all activities for a quarter
  def approve
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Skip authorization check for AJAX requests to prevent CanCan errors
    if request.xhr? || params[:action_type].present?
      # For AJAX requests, we'll handle authorization in the processing method
    else
      unless can_act_as_l1?(@employee_detail)
        redirect_back fallback_location: root_path, alert: "❌ You are not authorized to approve this record"
        return
      end
    end

    if can_act_as_l1?(@employee_detail)
      Rails.logger.debug "PROCESSING L1 QUARTERLY APPROVAL"
      # Pass action_type parameter to indicate this is an approval action
      params[:action_type] = "approve"
      result = process_quarterly_l1_approval

      if result[:success]
        if request.xhr? || params[:action_type].present?
          render json: {
            success: true,
            count: result[:count],
            message: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L1",
            updated_status: "l1_approved"
          }
        else
          redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                      notice: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L1"
        end
      else
        if request.xhr? || params[:action_type].present?
          render json: { success: false, message: result[:message] }, status: :unprocessable_entity
        else
          redirect_back fallback_location: root_path, alert: result[:message]
        end
      end

    elsif can_act_as_l2?(@employee_detail)
      Rails.logger.debug "PROCESSING L2 QUARTERLY APPROVAL"
      # Pass action_type parameter to indicate this is an approval action
      params[:action_type] = "approve"
      result = process_quarterly_l2_approval

      if result[:success]
        if request.xhr? || params[:action_type].present?
          render json: {
            success: true,
            count: result[:count],
            message: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
          }
        else
          redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                      notice: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
        end
      else
        if request.xhr? || params[:action_type].present?
          render json: { success: false, message: result[:message] }
        else
          redirect_back fallback_location: root_path, alert: result[:message]
        end
      end
    else
      Rails.logger.debug "AUTHORIZATION FAILED"
      if request.xhr? || params[:action_type].present?
        render json: { success: false, message: "❌ You are not authorized to approve this record" }
      else
        redirect_back fallback_location: root_path, alert: "❌ You are not authorized to approve this record"
      end
    end
  end

  # Quarterly return - return all activities for a quarter
  def return
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Skip authorization check for AJAX requests to prevent CanCan errors
    if request.xhr? || params[:action_type].present?
      # For AJAX requests, we'll handle authorization in the processing method
    else
      unless can_act_as_l1?(@employee_detail)
        redirect_back fallback_location: root_path, alert: "❌ You are not authorized to return this record"
        return
      end
    end

    if can_act_as_l1?(@employee_detail)
      Rails.logger.debug "PROCESSING L1 QUARTERLY RETURN"
      # Pass action_type parameter to indicate this is a return action
      params[:action_type] = "return"
      result = process_quarterly_l1_return

      if result[:success]
        if request.xhr? || params[:action_type].present?
          render json: {
            success: true,
            count: result[:count],
            message: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L1",
            updated_status: "l1_returned"
          }
        else
          redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                      alert: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L1"
        end
      else
        if request.xhr? || params[:action_type].present?
          render json: { success: false, message: result[:message] }, status: :unprocessable_entity
        else
          redirect_back fallback_location: root_path, alert: result[:message]
        end
      end

    elsif can_act_as_l2?(@employee_detail)
      Rails.logger.debug "PROCESSING L2 QUARTERLY RETURN"
      # Pass action_type parameter to indicate this is a return action
      params[:action_type] = "return"
      result = process_quarterly_l2_return

      if result[:success]
        if request.xhr? || params[:action_type].present?
          render json: {
            success: true,
            count: result[:count],
            message: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
          }
        else
          redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                      alert: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
        end
      else
        if request.xhr? || params[:action_type].present?
          render json: { success: false, message: result[:message] }
        else
          redirect_back fallback_location: root_path, alert: result[:message]
        end
      end
    else
      Rails.logger.debug "AUTHORIZATION FAILED"
      if request.xhr? || params[:action_type].present?
        render json: { success: false, message: "❌ You are not authorized to return this record" }
      else
        redirect_back fallback_location: root_path, alert: result[:message]
      end
    end
  end

def l2
  if current_user.hod?
    # HOD can see all employee details, but only those with L1+ approved achievements
    # PERFORMANCE FIX: Optimize includes to preload all necessary associations
    employee_details = EmployeeDetail.includes(
      user_details: [
        :activity,
        :department,
        achievements: :achievement_remark
      ]
    ).order(created_at: :desc)
  else
    # L2 managers can only see their assigned employees with L1+ approved achievements
    # PERFORMANCE FIX: Optimize includes to preload all necessary associations
    employee_details = EmployeeDetail.where("l2_code = ? OR l2_employer_name = ?",
                                           current_user.employee_code,
                                           current_user.email)
                                   .includes(
                                     user_details: [
                                       :activity,
                                       :department,
                                       achievements: :achievement_remark
                                     ]
                                   )
                                   .order(created_at: :desc)
  end

  # Filter to only include employees who have at least one L1+ approved achievement
  @employee_details = employee_details.select do |emp|
    financial_year_user_details_for(emp).any? do |ud|
      ud.achievements.any? do |achievement|
        # Only show records with L1 approved, L2 approved, or L2 returned status
        [ "l1_approved", "l2_approved", "l2_returned" ].include?(achievement.status)
      end
    end
  end
end

  def show_l2
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      return
    end

    unless current_user.hod? || can_act_as_l2?(@employee_detail)
      redirect_to root_path, alert: "❌ You are not authorized to access this page."
      return
    end

    @user_detail_id = params[:user_detail_id]
    @selected_quarter = params[:quarter]

    # FIXED: Get ALL user details, not just those with achievements
    @user_details = financial_year_user_details_for(@employee_detail)
                      .includes(:activity, :department, achievements: :achievement_remark)

    # If quarter is selected, filter achievements by quarter
    if @selected_quarter.present?
      @quarterly_activities = get_quarterly_activities(@user_details, @selected_quarter)
    else
      @quarterly_activities = get_all_quarterly_activities(@user_details)
    end

    @can_l2_approve_or_return = can_act_as_l2?(@employee_detail)
    @can_l2_act = @can_l2_approve_or_return
  end

  def l2_approve
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Employee detail not found: #{params[:id]}"
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Skip authorization check for AJAX requests to prevent CanCan errors
    if request.xhr? || params[:action_type].present?
      # For AJAX requests, we'll handle authorization in the processing method
    else
      unless current_user.hod? || can_act_as_l2?(@employee_detail)
        redirect_to show_l2_employee_detail_path(@employee_detail, financial_year: selected_financial_year), alert: "❌ You are not authorized to approve at L2 level"
        return
      end
    end

    # Pass action_type parameter to indicate this is an approval action
    params[:action_type] = "approve"
    result = process_quarterly_l2_approval

    if result[:success]
      if request.xhr? || params[:action_type].present?
        render json: {
          success: true,
          count: result[:count],
          message: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2",
          updated_status: "l2_approved"
        }
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    notice: "✅ Successfully approved #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
      end
    else
      if request.xhr? || params[:action_type].present?
        render json: { success: false, message: result[:message] }, status: :unprocessable_entity
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    alert: result[:message]
      end
    end
  end

  def l2_return
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Employee detail not found: #{params[:id]}"
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Skip authorization check for AJAX requests to prevent CanCan errors
    if request.xhr? || params[:action_type].present?
      # For AJAX requests, we'll handle authorization in the processing method
    else
      unless current_user.hod? || can_act_as_l2?(@employee_detail)
        redirect_to show_l2_employee_detail_path(@employee_detail, financial_year: selected_financial_year), alert: "❌ You are not authorized to return at L2 level"
        return
      end
    end

    # Add debugging

    # Pass action_type parameter to indicate this is a return action
    params[:action_type] = "return"
    result = process_quarterly_l2_return


    if result[:success]
      if request.xhr? || params[:action_type].present?
        render json: {
          success: true,
          count: result[:count],
          message: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2",
          updated_status: "l2_returned"
        }
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    notice: "⚠️ Successfully returned #{result[:count]} activities for #{params[:selected_quarter] || 'all quarters'} by L2"
      end
    else
      if request.xhr? || params[:action_type].present?
        render json: { success: false, message: result[:message] }, status: :unprocessable_entity
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    alert: result[:message]
      end
    end
  end

  # Edit L1 remarks and percentage
  def edit_l1
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Employee detail not found: #{params[:id]}"
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Only HOD can edit L1 data
    unless current_user.hod?
      if request.xhr?
        render json: { success: false, message: "❌ You are not authorized to edit L1 data" }, status: :forbidden
      else
        redirect_to root_path, alert: "❌ You are not authorized to edit L1 data."
      end
      return
    end

    result = process_l1_edit

    if result[:success]
      if request.xhr?
        render json: {
          success: true,
          message: "✅ Successfully updated L1 data for #{params[:selected_quarter] || 'all quarters'}",
          percentage: result[:percentage],
          remarks: result[:remarks]
        }
      else
        redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    notice: "✅ Successfully updated L1 data for #{params[:selected_quarter] || 'all quarters'}"
      end
    else
      if request.xhr?
        render json: { success: false, message: result[:message] }, status: :unprocessable_entity
      else
        redirect_to employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    alert: result[:message]
      end
    end
  end

  # Edit L2 remarks and percentage
  def edit_l2
    begin
      @employee_detail = EmployeeDetail.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Employee detail not found: #{params[:id]}"
      if request.xhr?
        render json: { success: false, message: "❌ Employee detail not found. The record may have been deleted." }, status: :not_found
      else
        redirect_to employee_details_path, alert: "❌ Employee detail not found. The record may have been deleted."
      end
      return
    end

    # Only HOD can edit L2 data
    unless current_user.hod?
      if request.xhr?
        render json: { success: false, message: "❌ You are not authorized to edit L2 data" }, status: :forbidden
      else
        redirect_to root_path, alert: "❌ You are not authorized to edit L2 data."
      end
      return
    end

    result = process_l2_edit

    if result[:success]
      if request.xhr?
        render json: {
          success: true,
          message: "✅ Successfully updated L2 data for #{params[:selected_quarter] || 'all quarters'}",
          percentage: result[:percentage],
          remarks: result[:remarks]
        }
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    notice: "✅ Successfully updated L2 data for #{params[:selected_quarter] || 'all quarters'}"
      end
    else
      if request.xhr?
        render json: { success: false, message: result[:message] }, status: :unprocessable_entity
      else
        redirect_to show_l2_employee_detail_path(@employee_detail, quarter: params[:selected_quarter], financial_year: selected_financial_year),
                    alert: result[:message]
      end
    end
  end

  private

  def normalize_import_header(value)
    value.to_s.strip.downcase.gsub(/[^a-z0-9#]+/, "")
  end

  def find_existing_employee_detail(mapped_row)
    if mapped_row["employee_code"].present?
      employee = EmployeeDetail.find_by(employee_code: mapped_row["employee_code"])
      return employee if employee
    end

    if mapped_row["employee_email"].present?
      employee = EmployeeDetail.find_by(employee_email: mapped_row["employee_email"])
      return employee if employee
    end

    if mapped_row["employee_name"].present? && mapped_row["mobile_number"].present?
      employee = EmployeeDetail.find_by(
        employee_name: mapped_row["employee_name"],
        mobile_number: mapped_row["mobile_number"]
      )
      return employee if employee
    end

    if mapped_row["employee_id"].present?
      employee = EmployeeDetail.find_by(employee_id: mapped_row["employee_id"])
      return employee if employee
    end

    nil
  end

  def set_employee_detail
    @employee_detail = EmployeeDetail.find(params[:id])
  end

  def employee_detail_params
    params.require(:employee_detail).permit(
      :employee_id, :employee_name, :employee_email, :employee_code, :mobile_number,
      :l1_code, :l1_employer_name, :l2_code, :l2_employer_name,
      :post, :department, :l1_remarks, :l1_percentage, :l2_remarks, :l2_percentage
    )
  end

  def financial_year_user_details_for(record_or_collection)
    collection = record_or_collection.respond_to?(:user_details) ? record_or_collection.user_details : record_or_collection

    if collection.respond_to?(:loaded?) && collection.loaded?
      Array(collection).select do |detail|
        detail.financial_year == selected_financial_year && assignment_consistent_for_employee?(detail)
      end
    elsif collection.respond_to?(:where)
      collection.assignment_consistent.where(financial_year: selected_financial_year)
    else
      Array(collection).select do |detail|
        detail.financial_year == selected_financial_year && assignment_consistent_for_employee?(detail)
      end
    end
  end

  def assignment_consistent_for_employee?(detail)
    return false if detail.blank? || detail.department.blank? || detail.activity.blank? || detail.employee_detail.blank?
    return false unless detail.activity.department_id == detail.department_id

    department_reference = detail.department.employee_reference.to_s.strip
    return true if department_reference.blank?

    employee_references = [ detail.employee_detail.employee_id, detail.employee_detail.employee_code ].compact_blank
    return false if employee_references.empty?

    employee_references.include?(department_reference)
  end

  def can_act_as_l1?(employee_detail)
    current_user.hod? ||
    current_user.employee_code == employee_detail.l1_code ||
    current_user.email == employee_detail.l1_employer_name
  end

  def can_act_as_l2?(employee_detail)
    current_user.hod? ||
    current_user.employee_code == employee_detail.l2_code ||
    current_user.email == employee_detail.l2_employer_name
  end

  def get_quarter_months(quarter)
    case quarter
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
  end

  def get_all_quarters
    [ "Q1", "Q2", "Q3", "Q4" ]
  end

  # Group employees by quarters based on their activities (FIXED to show ALL activities)
  def group_employees_by_quarters(employee_details)
    quarterly_data = {}

    get_all_quarters.each do |quarter|
      quarterly_data[quarter] = {
        employees: [],
        total_activities: 0,
        pending_activities: 0,
        approved_activities: 0,
        quarter_months: get_quarter_months(quarter)
      }
    end

    employee_details.each do |employee|
      get_all_quarters.each do |quarter|
        quarter_months = get_quarter_months(quarter)

        # FIXED: Get ALL activities for this quarter, not just those with achievements
        quarter_activities = financial_year_user_details_for(employee).select do |detail|
          detail.department&.department_type == employee.department
        end

        if quarter_activities.any?
          employee_quarter_data = {
            employee: employee,
            activities: [],
            total_count: 0,
            pending_count: 0,
            approved_count: 0,
            overall_status: "pending"
          }

          # PERFORMANCE FIX: Preload achievements to avoid N+1 queries
          quarter_activities.each do |user_detail|
            # PERFORMANCE FIX: Create a hash of achievements by month for fast lookup
            achievements_by_month = user_detail.achievements.index_by(&:month)

            # Check each month in the quarter for targets
            quarter_months.each do |month|
              target_value = get_target_for_month(user_detail, month)
              next unless target_value.present? && target_value.to_s != "0"

              # PERFORMANCE FIX: Use in-memory hash lookup instead of database query
              achievement = achievements_by_month[month]

              activity_data = {
                user_detail: user_detail,
                achievement: achievement,
                month: month,
                activity_name: user_detail.activity&.activity_name,
                department: user_detail.department&.department_type,
                target: target_value,
                achievement_value: achievement&.achievement || "",
                status: achievement&.status || "pending",
                has_target: true
              }

              employee_quarter_data[:activities] << activity_data
              employee_quarter_data[:total_count] += 1

              case achievement&.status
              when "l1_approved", "l2_approved"
                employee_quarter_data[:approved_count] += 1
              else
                employee_quarter_data[:pending_count] += 1
              end
            end
          end

          # Determine overall status for this employee in this quarter
          if employee_quarter_data[:approved_count] == employee_quarter_data[:total_count] && employee_quarter_data[:total_count] > 0
            employee_quarter_data[:overall_status] = "approved"
          elsif employee_quarter_data[:pending_count] > 0
            employee_quarter_data[:overall_status] = "pending"
          end

          quarterly_data[quarter][:employees] << employee_quarter_data
          quarterly_data[quarter][:total_activities] += employee_quarter_data[:total_count]
          quarterly_data[quarter][:pending_activities] += employee_quarter_data[:pending_count]
          quarterly_data[quarter][:approved_activities] += employee_quarter_data[:approved_count]
        end
      end
    end

    quarterly_data
  end

  # Get quarterly activities for a specific quarter
  def get_quarterly_activities(user_details, quarter)
    # Use the new comprehensive method
    get_all_activities_for_quarter(user_details, quarter)
  end

  # Get all quarterly activities grouped by quarter - FIXED to show ALL activities
  def get_all_quarterly_activities(user_details)
    all_activities = {}

    get_all_quarters.each do |quarter|
      all_activities[quarter] = get_quarterly_activities(user_details, quarter)
    end

    all_activities
  end

  # NEW: Get all activities for a specific quarter (including those without achievements)
  def get_all_activities_for_quarter(user_details, quarter)
    quarter_months = get_quarter_months(quarter)
    activities = []

    user_details.each do |user_detail|
      # PERFORMANCE FIX: Create a hash of achievements by month for fast lookup
      achievements_by_month = user_detail.achievements.index_by(&:month)

      quarter_months.each do |month|
        # Check if there's a target for this month
        target_value = get_target_for_month(user_detail, month)
        next unless target_value.present? && target_value.to_s != "0"

        # PERFORMANCE FIX: Use in-memory hash lookup instead of database query
        achievement = achievements_by_month[month]

        # Create activity data regardless of whether achievement exists
        activity_data = {
          user_detail: user_detail,
          achievement: achievement,
          month: month,
          activity_name: user_detail.activity&.activity_name,
          department: user_detail.department&.department_type,
          target: target_value,
          achievement_value: achievement&.achievement || "",
          status: achievement&.status || "pending",
          employee_remarks: achievement&.employee_remarks || "",
          has_target: true,
          can_approve: can_approve_activity?(achievement),
          can_return: can_return_activity?(achievement)
        }

        activities << activity_data
      end
    end

    activities.sort_by { |a| [ a[:month], a[:activity_name] ] }
  end

  # Helper method to check if an activity can be approved
  def can_approve_activity?(achievement)
    return false unless achievement
    [ "pending", "l1_returned", "l2_returned" ].include?(achievement.status)
  end

  # Helper method to check if an activity can be returned
  def can_return_activity?(achievement)
    return false unless achievement
    [ "pending", "l1_approved", "l2_approved" ].include?(achievement.status)
  end

  # Helper method to get overall quarter status
  def get_quarter_overall_status(activities)
    return "no_data" if activities.empty?

    statuses = activities.map { |a| a[:status] }

    # FIXED: L2 statuses should take highest priority
    # If ANY activity has L2 approved, the quarter is L2 approved
    if statuses.include?("l2_approved")
      "l2_approved"
    # If ANY activity has L2 returned, the quarter is L2 returned
    elsif statuses.include?("l2_returned")
      "l2_returned"
    # If ALL activities are L1 approved, the quarter is L1 approved
    elsif statuses.all? { |s| [ "l1_approved" ].include?(s) }
      "l1_approved"
    # If ANY activity has L1 returned, the quarter is L1 returned
    elsif statuses.any? { |s| [ "l1_returned" ].include?(s) }
      "l1_returned"
    # If ANY activity has submitted status, the quarter is submitted
    elsif statuses.any? { |s| [ "submitted" ].include?(s) }
      "submitted"
    else
      "pending"
    end
  end

  # Get all activities that can be approved/returned for a specific quarter
  def get_approvable_activities_for_quarter(user_details, quarter, approval_level = "l1")
    quarter_months = get_quarter_months(quarter)
    approvable_activities = []

    user_details.each do |user_detail|
      # PERFORMANCE FIX: Create a hash of achievements by month for fast lookup
      achievements_by_month = user_detail.achievements.index_by(&:month)

      quarter_months.each do |month|
        # Check if there's a target for this month
        target_value = get_target_for_month(user_detail, month)
        next unless target_value.present? && target_value.to_s != "0"

        # PERFORMANCE FIX: Use in-memory hash lookup instead of database query
        achievement = achievements_by_month[month]

        # Check if this activity can be approved/returned at the specified level
        can_act = case approval_level
        when "l1"
          can_approve_activity?(achievement) || can_return_activity?(achievement)
        when "l2"
          achievement && [ "l1_approved", "l2_returned" ].include?(achievement.status)
        else
          false
        end

        next unless can_act

        approvable_activities << {
          user_detail: user_detail,
          achievement: achievement,
          month: month,
          activity_name: user_detail.activity&.activity_name,
          department: user_detail.department&.department_type,
          target: target_value,
          achievement_value: achievement&.achievement || "",
          status: achievement&.status || "pending",
          employee_remarks: achievement&.employee_remarks || "",
          can_approve: can_approve_activity?(achievement),
          can_return: can_return_activity?(achievement)
        }
      end
    end

    approvable_activities.sort_by { |a| [ a[:month], a[:activity_name] ] }
  end

  # Get target value for a specific month
  def get_target_for_month(user_detail, month)
    return nil unless user_detail.respond_to?(month.to_sym)
    user_detail.send(month.to_sym)
  end

  def process_quarterly_l1_approval
    # Add authorization check here for AJAX requests
    unless can_act_as_l1?(@employee_detail)
      return { success: false, message: "❌ You are not authorized to perform L1 actions on this record" }
    end

    approved_count = 0

    # Determine if this is an approval or return action
    action_type = params[:action_type] || "approve"
    is_approval = action_type.include?("approve")
    new_status = is_approval ? "l1_approved" : "l1_returned"

    if params[:selected_quarter].present?
      # FIXED: Approve/Return specific quarter as a single unit
      quarter_months = get_quarter_months(params[:selected_quarter])

      financial_year_user_details_for(@employee_detail).each do |detail|
        # FIXED: Process the entire quarter as one unit, not month by month
        quarter_achievements = []

        # First, collect all achievements for this quarter
        quarter_months.each do |month|
          # FIXED: Process ALL months in the quarter, not just those with targets
          # This ensures the entire quarter gets approved when L1 approves


          # Find or create achievement for this month
          achievement = detail.achievements.find_or_create_by(month: month)


          # Ensure achievement is saved and has an ID
          achievement.save! if achievement.new_record?

          # Add to quarter achievements list
          quarter_achievements << achievement
        end

        # FIXED: Now process the entire quarter as one unit
        if quarter_achievements.any?

          # FIXED: Update ALL achievements in the quarter to the same status
          quarter_achievements.each do |achievement|
            old_status = achievement.status
            achievement.update!(status: new_status)

            # Create or update achievement remark with COMMON remarks for quarter
            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l1_remarks = params[:remarks] if params[:remarks].present?
            remark.l1_percentage = params[:percentage] if params[:percentage].present?
            remark.save!

            approved_count += 1
          end

        else
          Rails.logger.warn "No achievements found for quarter #{params[:selected_quarter]} in activity #{detail.activity.activity_name}"
        end
      end
    else
      # Approve/Return all quarters
      financial_year_user_details_for(@employee_detail).each do |detail|
        get_all_quarters.each do |quarter|
          quarter_months = get_quarter_months(quarter)

          quarter_months.each do |month|
            # FIXED: Process ALL months in the quarter, not just those with targets
            # This ensures the entire quarter gets approved when processing all quarters

            # Find or create achievement for this month
            achievement = detail.achievements.find_or_create_by(month: month)

            # Ensure achievement is saved and has an ID
            achievement.save! if achievement.new_record?

            # Update achievement status
            achievement.update!(status: new_status)

            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l1_remarks = params[:remarks] if params[:remarks].present?
            remark.l1_percentage = params[:percentage] if params[:percentage].present?
            remark.save!

            approved_count += 1
          end
        end
      end
    end

    if approved_count > 0
      { success: true, count: approved_count }
    else
      action_text = is_approval ? "approve" : "return"
      { success: false, message: "❌ No activities found to #{action_text} for the selected quarter" }
    end
  end

# Process L1 quarterly return - FIXED
def process_quarterly_l1_return
  # This method now delegates to the approval method since it handles both approve and return
  process_quarterly_l1_approval
end

# Process L2 quarterly approval - FIXED
def process_quarterly_l2_approval
  # Add authorization check here for AJAX requests
  unless current_user.hod? || can_act_as_l2?(@employee_detail)
    return { success: false, message: "❌ You are not authorized to perform L2 actions on this record" }
  end

  approved_count = 0

  # Determine if this is an approval or return action
  action_type = params[:action_type] || "approve"
  is_approval = action_type.include?("approve")
  new_status = is_approval ? "l2_approved" : "l2_returned"


  if params[:selected_quarter].present?
    # FIXED: Approve/Return specific quarter as a single unit
    quarter_months = get_quarter_months(params[:selected_quarter])

    financial_year_user_details_for(@employee_detail).each do |detail|
      # FIXED: Process the entire quarter as one unit, not month by month
      quarter_achievements = []

      # First, collect all achievements for this quarter
      quarter_months.each do |month|
        # FIXED: Process ALL months in the quarter, not just those with targets
        # This ensures the entire quarter gets approved when L2 approves


        # Find or create achievement for this month
        achievement = detail.achievements.find_or_create_by(month: month)

        # Ensure achievement is saved and has an ID
        achievement.save! if achievement.new_record?

        # Add to quarter achievements list
        quarter_achievements << achievement
      end

      # FIXED: Now process the entire quarter as one unit
      if quarter_achievements.any?

        # Update ALL achievements in the quarter to the same status
        quarter_achievements.each do |achievement|
          # For L2 return, we should be able to return L1 approved achievements
          # For L2 approve, we need L1 approved or L2 returned achievements
          if is_approval
            # For approval, check eligibility
            eligible_statuses = [ "l1_approved", "l2_returned" ]
            if eligible_statuses.include?(achievement.status)
              old_status = achievement.status
              achievement.update!(status: new_status)

              # Create or update achievement remark with COMMON remarks for quarter
              remark = achievement.achievement_remark || achievement.build_achievement_remark
              remark.l2_remarks = params[:l2_remarks] || params[:remarks] if params[:l2_remarks].present? || params[:remarks].present?
              remark.l2_percentage = params[:l2_percentage] || params[:percentage] if params[:l2_percentage].present? || params[:percentage].present?
              remark.save!

              approved_count += 1
            else
            end
          else
            # For return, process ALL achievements regardless of current status
            old_status = achievement.status
            achievement.update!(status: new_status)

            # Create or update achievement remark with COMMON remarks for quarter
            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l2_remarks = params[:l2_remarks] || params[:remarks] if params[:l2_remarks].present? || params[:remarks].present?
            remark.l2_percentage = params[:l2_percentage] || params[:percentage] if params[:l2_percentage].present? || params[:percentage].present?
            remark.save!

            approved_count += 1
          end
        end

      else
        Rails.logger.warn "No achievements found for quarter #{params[:selected_quarter]} in activity #{detail.activity.activity_name}"
      end
    end
  else
    # Approve/Return all quarters
    financial_year_user_details_for(@employee_detail).each do |detail|
      get_all_quarters.each do |quarter|
        quarter_months = get_quarter_months(quarter)

        quarter_months.each do |month|
          # FIXED: Process ALL months in the quarter, not just those with targets
          # This ensures the entire quarter gets approved when processing all quarters

          # Find or create achievement for this month
          achievement = detail.achievements.find_or_create_by(month: month)

          # Ensure achievement is saved and has an ID
          achievement.save! if achievement.new_record?

          # For L2 return, we should be able to return L1 approved achievements
          # For L2 approve, we need L1 approved or L2 returned achievements
          eligible_statuses = is_approval ? [ "l1_approved", "l2_returned" ] : [ "l1_approved" ]

          if eligible_statuses.include?(achievement.status)
            # Update achievement status
            achievement.update!(status: new_status)

            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l2_remarks = params[:l2_remarks] || params[:remarks] if params[:l2_remarks].present? || params[:remarks].present?
            remark.l2_percentage = params[:l2_percentage] || params[:percentage] if params[:l2_percentage].present? || params[:percentage].present?
            remark.save!

            approved_count += 1
          end
        end
      end
    end
  end

  if approved_count > 0
    { success: true, count: approved_count }
  else
    action_text = is_approval ? "approve" : "return"
    { success: false, message: "❌ No L1 approved activities found to #{action_text} for the selected quarter" }
  end
end

  # Process L2 quarterly return - FIXED
  def process_quarterly_l2_return
    # This method now delegates to the approval method since it handles both approve and return
    process_quarterly_l2_approval
  end


  # PERFORMANCE FIX: Pre-calculate summary data to avoid processing in view
  def calculate_summary_data(employee_details)
    summary_data = {
      total_quarterly_records: 0,
      l1_approved_count: 0,
      l2_approved_count: 0,
      pending_count: 0,
      returned_count: 0,
      submitted_count: 0,
      employee_quarter_statuses: {}
    }

    quarters = {
      "Q1" => [ "april", "may", "june" ],
      "Q2" => [ "july", "august", "september" ],
      "Q3" => [ "october", "november", "december" ],
      "Q4" => [ "january", "february", "march" ]
    }

    employee_details.each do |emp|
      quarters.each do |quarter_name, quarter_months|
        # PERFORMANCE FIX: Use preloaded associations instead of flat_map
        all_quarter_achievements = financial_year_user_details_for(emp).flat_map(&:achievements).select { |ach| quarter_months.include?(ach.month) }

        next if all_quarter_achievements.empty?

        summary_data[:total_quarterly_records] += 1

        # PERFORMANCE FIX: More efficient status calculation
        current_status = calculate_quarter_status(all_quarter_achievements)

        # Store status for this employee-quarter combination
        summary_data[:employee_quarter_statuses]["#{emp.id}_#{quarter_name}"] = current_status

        # Update counters
        case current_status
        when "l1_approved"
          summary_data[:l1_approved_count] += 1
        when "l2_approved"
          summary_data[:l2_approved_count] += 1
        when "l1_returned", "l2_returned"
          summary_data[:returned_count] += 1
        when "submitted"
          summary_data[:submitted_count] += 1
        else
          summary_data[:pending_count] += 1
        end
      end
    end

    summary_data
  end

  # PERFORMANCE FIX: Optimized status calculation method
  def calculate_quarter_status(quarter_achievements)
    helpers.calculate_overall_quarter_status_from_achievements(quarter_achievements)
  end

  # Build the quarterly employee data structure expected by the view
  def build_quarterly_employee_data(employee_details)
    quarterly_employee_data = {}

    quarters = {
      "Q1" => [ "april", "may", "june" ],
      "Q2" => [ "july", "august", "september" ],
      "Q3" => [ "october", "november", "december" ],
      "Q4" => [ "january", "february", "march" ]
    }

    employee_details.each do |emp|
      quarters.each do |quarter_name, quarter_months|
        # Get all achievements for this employee in this quarter
        all_quarter_achievements = financial_year_user_details_for(emp).flat_map(&:achievements).select { |ach| quarter_months.include?(ach.month) }

        # Only include if there are achievements in this quarter
        if all_quarter_achievements.any?
          # Calculate quarter status
          current_status = calculate_quarter_status(all_quarter_achievements)
          status_config = get_status_config(current_status)

          # Create unique key for this employee-quarter combination
          key = "#{emp.id}_#{quarter_name}"

          quarterly_employee_data[key] = {
            employee: emp,
            quarter_name: quarter_name,
            quarter_months: quarter_months,
            status: current_status,
            status_config: status_config
          }
        end
      end
    end

    quarterly_employee_data
  end

  # Get status configuration for display
  def get_status_config(status)
    case status
    when "l1_approved"
      { color: "bg-green-100 text-green-800 border-green-300", text: "L1 Approved" }
    when "l2_approved"
      { color: "bg-green-600 text-white border-green-700", text: "L2 Approved" }
    when "l1_returned"
      { color: "bg-red-100 text-red-800 border-red-300", text: "L1 Returned" }
    when "l2_returned"
      { color: "bg-orange-100 text-orange-800 border-orange-300", text: "L2 Returned" }
    when "submitted"
      { color: "bg-blue-100 text-blue-800 border-blue-300", text: "Submitted" }
    else
      { color: "bg-yellow-100 text-yellow-800 border-yellow-300", text: "Pending" }
    end
  end

  # Process L1 edit - update L1 remarks and percentage for a quarter
  def process_l1_edit
    updated_count = 0

    if params[:selected_quarter].present?
      # Update specific quarter
      quarter_months = get_quarter_months(params[:selected_quarter])

      financial_year_user_details_for(@employee_detail).each do |detail|
        quarter_months.each do |month|
          # Find or create achievement for this month
          achievement = detail.achievements.find_or_create_by(month: month)
          achievement.save! if achievement.new_record?

          # Create or update achievement remark with L1 data
          remark = achievement.achievement_remark || achievement.build_achievement_remark
          remark.l1_remarks = params[:l1_remarks] if params[:l1_remarks].present?
          remark.l1_percentage = params[:l1_percentage] if params[:l1_percentage].present?
          remark.save!

          updated_count += 1
        end
      end
    else
      # Update all quarters
      financial_year_user_details_for(@employee_detail).each do |detail|
        get_all_quarters.each do |quarter|
          quarter_months = get_quarter_months(quarter)

          quarter_months.each do |month|
            # Find or create achievement for this month
            achievement = detail.achievements.find_or_create_by(month: month)
            achievement.save! if achievement.new_record?

            # Create or update achievement remark with L1 data
            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l1_remarks = params[:l1_remarks] if params[:l1_remarks].present?
            remark.l1_percentage = params[:l1_percentage] if params[:l1_percentage].present?
            remark.save!

            updated_count += 1
          end
        end
      end
    end

    if updated_count > 0
      { success: true, count: updated_count, percentage: params[:l1_percentage], remarks: params[:l1_remarks] }
    else
      { success: false, message: "❌ No activities found to update for the selected quarter" }
    end
  end

  # Process L2 edit - update L2 remarks and percentage for a quarter
  def process_l2_edit
    updated_count = 0

    if params[:selected_quarter].present?
      # Update specific quarter
      quarter_months = get_quarter_months(params[:selected_quarter])

      financial_year_user_details_for(@employee_detail).each do |detail|
        quarter_months.each do |month|
          # Find or create achievement for this month
          achievement = detail.achievements.find_or_create_by(month: month)
          achievement.save! if achievement.new_record?

          # Create or update achievement remark with L2 data
          remark = achievement.achievement_remark || achievement.build_achievement_remark
          remark.l2_remarks = params[:l2_remarks] if params[:l2_remarks].present?
          remark.l2_percentage = params[:l2_percentage] if params[:l2_percentage].present?
          remark.save!

          updated_count += 1
        end
      end
    else
      # Update all quarters
      financial_year_user_details_for(@employee_detail).each do |detail|
        get_all_quarters.each do |quarter|
          quarter_months = get_quarter_months(quarter)

          quarter_months.each do |month|
            # Find or create achievement for this month
            achievement = detail.achievements.find_or_create_by(month: month)
            achievement.save! if achievement.new_record?

            # Create or update achievement remark with L2 data
            remark = achievement.achievement_remark || achievement.build_achievement_remark
            remark.l2_remarks = params[:l2_remarks] if params[:l2_remarks].present?
            remark.l2_percentage = params[:l2_percentage] if params[:l2_percentage].present?
            remark.save!

            updated_count += 1
          end
        end
      end
    end

    if updated_count > 0
      { success: true, count: updated_count, percentage: params[:l2_percentage], remarks: params[:l2_remarks] }
    else
      { success: false, message: "❌ No activities found to update for the selected quarter" }
    end
  end
end
