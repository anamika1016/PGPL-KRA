require "roo"

class HelpDeskQuestionMastersController < ApplicationController
  VALID_IMPORT_EXTENSIONS = %w[.xlsx .xls .csv].freeze
  REQUEST_TYPE_ALIASES = {
    "ticket" => "ticket",
    "tickets" => "ticket",
    "complaint" => "complaint",
    "complaints" => "complaint",
    "suggestion" => "suggestion",
    "suggestions" => "suggestion"
  }.freeze
  HEADER_ALIASES = {
    "department" => "department",
    "department name" => "department",
    "department type" => "department",
    "vertical" => "department",
    "request type" => "request_type",
    "type" => "request_type",
    "question" => "question_text",
    "question topic" => "question_text",
    "question / topic" => "question_text",
    "topic" => "question_text",
    "active" => "active",
    "status" => "active"
  }.freeze

  before_action :ensure_hod!
  before_action :set_help_desk_question_master, only: [ :edit, :update, :destroy ]
  before_action :load_help_desk_question_support_data, only: [ :index, :create, :edit, :update ]

  def index
    @help_desk_question_master = HelpDeskQuestionMaster.new(active: true)
  end

  def create
    @help_desk_question_master = HelpDeskQuestionMaster.new(help_desk_question_master_params)

    if @help_desk_question_master.save
      redirect_to help_desk_question_masters_path, notice: "Help desk question created successfully."
    else
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    render :index
  end

  def update
    if @help_desk_question_master.update(help_desk_question_master_params)
      redirect_to help_desk_question_masters_path, notice: "Help desk question updated successfully."
    else
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @help_desk_question_master.destroy
    redirect_to help_desk_question_masters_path, notice: "Help desk question deleted successfully."
  end

  def import
    file = params[:file]

    unless valid_import_file?(file)
      redirect_to help_desk_question_masters_path, alert: "Please upload a valid .xlsx, .xls, or .csv file."
      return
    end

    result = import_questions_from_file(file)
    message = "Imported #{result[:created]} question(s). Skipped #{result[:skipped]} duplicate/blank row(s)."

    if result[:errors].any?
      redirect_to help_desk_question_masters_path,
                  alert: "#{message} Some rows failed: #{result[:errors].first(5).join('; ')}"
    else
      redirect_to help_desk_question_masters_path, notice: message
    end
  rescue Roo::Error, ArgumentError => e
    redirect_to help_desk_question_masters_path, alert: "Question import failed: #{e.message}"
  end

  private

  def set_help_desk_question_master
    @help_desk_question_master = HelpDeskQuestionMaster.find(params[:id])
  end

  def load_help_desk_question_support_data
    @departments = Department.selectable_verticals
    @help_desk_question_masters = HelpDeskQuestionMaster.includes(:department).ordered_for_display
  end

  def help_desk_question_master_params
    params.require(:help_desk_question_master).permit(:department_id, :request_type, :question_text, :active)
  end

  def valid_import_file?(file)
    return false if file.blank?

    VALID_IMPORT_EXTENSIONS.include?(File.extname(file.original_filename).downcase)
  end

  def import_questions_from_file(file)
    spreadsheet = Roo::Spreadsheet.open(file.path, extension: File.extname(file.original_filename).delete_prefix("."))
    headers = spreadsheet.row(1).map { |header| import_header_key(header) }
    departments_by_name = Department.selectable_verticals.index_by { |department| normalize_import_value(department.department_type) }
    result = { created: 0, skipped: 0, errors: [] }

    if spreadsheet.last_row.to_i < 2 || headers.compact_blank.empty?
      result[:errors] << "No question rows found"
      return result
    end

    (2..spreadsheet.last_row).each do |row_number|
      attributes = Hash[headers.zip(spreadsheet.row(row_number))]
      import_question_row(attributes, departments_by_name, row_number, result)
    end

    result
  end

  def import_question_row(attributes, departments_by_name, row_number, result)
    department_name = attributes["department"].to_s.strip
    department = departments_by_name[normalize_import_value(department_name)]
    request_type = normalize_request_type(attributes["request_type"])
    question_text = attributes["question_text"].to_s.strip

    if department_name.blank? && request_type.blank? && question_text.blank?
      result[:skipped] += 1
      return
    end

    row_errors = []
    row_errors << "Department is required" if department_name.blank?
    row_errors << "Department '#{department_name}' was not found" if department_name.present? && department.blank?
    row_errors << "Request type must be Ticket, Complaint, or Suggestion" if request_type.blank?
    row_errors << "Question is required" if question_text.blank?

    if row_errors.any?
      result[:errors] << "Row #{row_number}: #{row_errors.join(', ')}"
      return
    end

    question = HelpDeskQuestionMaster.new(
      department: department,
      request_type: request_type,
      question_text: question_text,
      active: import_active_value(attributes["active"])
    )

    if duplicate_question?(question)
      result[:skipped] += 1
    elsif question.save
      result[:created] += 1
    else
      result[:errors] << "Row #{row_number}: #{question.errors.full_messages.to_sentence}"
    end
  end

  def import_header_key(value)
    HEADER_ALIASES[normalize_import_value(value)]
  end

  def normalize_import_value(value)
    value.to_s.strip.downcase.squish
  end

  def normalize_request_type(value)
    REQUEST_TYPE_ALIASES[normalize_import_value(value)]
  end

  def import_active_value(value)
    normalized_value = normalize_import_value(value)
    return true if normalized_value.blank?

    %w[active yes y true 1 enabled].include?(normalized_value)
  end

  def duplicate_question?(question)
    HelpDeskQuestionMaster
      .where(department_id: question.department_id, request_type: question.request_type)
      .where("LOWER(question_text) = ?", question.question_text.downcase)
      .exists?
  end

  def ensure_hod!
    return if current_user&.hod?

    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
