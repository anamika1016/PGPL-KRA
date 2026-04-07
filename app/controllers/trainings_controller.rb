class TrainingsController < ApplicationController
  before_action :authenticate_user!

  def index
    if current_user.role == "hod"
      @trainings = Training.includes(:user_training_progresses)
    else
      # Non-HOD users: check assignments_managed flag
      employee = current_user.employee_detail || EmployeeDetail.find_by(employee_email: current_user.email)
      if employee
        if employee.assignments_managed?
          # HOD has explicitly managed this employee's assignments → show ONLY assigned trainings
          assigned_ids = employee.user_training_assignments.pluck(:training_id)
          @trainings = Training.where(id: assigned_ids).includes(:user_training_progresses)
        else
          # Employee not yet managed by HOD → show ALL active trainings (default behaviour)
          @trainings = Training.includes(:user_training_progresses)
        end
      else
        @trainings = Training.none
      end
    end

    # Month & Year filter (separate check better hai)
    if params[:month].present?
      @trainings = @trainings.where(month: params[:month])
    end

    if params[:year].present?
      @trainings = @trainings.where(year: params[:year])
    end

    # ✅ NEW: Title Filter
    if params[:training_id].present?
      @trainings = @trainings.where(id: params[:training_id])
    end

    @trainings = @trainings.order(created_at: :desc)

    # For employees: build an ordered map of "best" progress per training.
    # This avoids issues when duplicate progress rows exist (e.g., old 'started' rows)
    # and ensures UI checks use the latest/most relevant record.
    if current_user.role != "hod"
      ordered_progresses = UserTrainingProgress
        .where(user_id: current_user.id, training_id: @trainings.select(:id))
        .order(
          Arel.sql("CASE WHEN status = 'completed' THEN 0 ELSE 1 END ASC"),
          ended_at: :desc,
          updated_at: :desc,
          id: :desc
        )

      @progress_by_training_id = {}
      ordered_progresses.each do |p|
        @progress_by_training_id[p.training_id] ||= p
      end
    end
  end

  def edit
    @training = Training.find(params[:id])
  end

  def update
    @training = Training.find(params[:id])

    # Prevent existing files from being cleared if no new ones are uploaded
    update_params = training_params
    if update_params[:files].blank? || (update_params[:files].is_a?(Array) && update_params[:files].all?(&:blank?))
      update_params.delete(:files)
    end

    if @training.update(update_params)
      if @training.has_assessment && params[:excel_file].present?
        import_questions_from_excel(@training, params[:excel_file])
      end
      redirect_to trainings_path, notice: "Training updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @training = Training.find(params[:id])
    @training.destroy
    redirect_to trainings_path, notice: "Training deleted successfully"
  end

  def toggle_status
    @training = Training.find(params[:id])
    @training.update(status: !@training.status)
    redirect_to trainings_path, notice: "Training status updated"
  end

  def new
    @training = Training.new
  end

  def create
    @training = Training.new(training_params)
    @training.created_by = current_user.id
    # Default status to Active so employees see it immediately
    @training.status = true if @training.status.nil?

    if @training.save
      if @training.has_assessment && params[:excel_file].present?
        import_questions_from_excel(@training, params[:excel_file])
      end

      # ✅ Auto-assign this new training to ALL already-managed employees
      # so it appears pre-ticked in their assignment list and visible in their login.
      # Unmanaged employees already see ALL trainings by default.
      EmployeeDetail.where(assignments_managed: true).each do |employee|
        employee.user_training_assignments.find_or_create_by(
          training_id: @training.id,
          user_id:     employee.user_id
        )
      end

      redirect_to trainings_path, notice: "Training uploaded successfully and assigned to all employees."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @training = Training.find(params[:id])

    # Load current user's progress for this training
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    @files = @training.files.map do |file|
      {
        name: file.filename.to_s,
        url: rails_blob_url(file, only_path: false)
      }
    end
  end

  # POST /trainings/:id/start_training
  # Called by JS when user opens the training page — records started_at
  def start_training
    @training = Training.find(params[:id])
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    unless @progress.status == "completed"
      @progress.status     = "started"
      @progress.started_at ||= Time.current
      @progress.financial_year = financial_year_for(@training.month, @training.year)
      @progress.save!
    end

    render json: {
      status: @progress.status,
      started_at: @progress.started_at,
      time_spent: @progress.time_spent.to_i
    }
  end

  # POST /trainings/:id/update_progress
  # Called by JS periodically or on visibilitychange/unload to save running time
  def update_progress
    @training = Training.find(params[:id])
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    if @progress.status == "started" && params[:time_spent].present?
      @progress.time_spent = params[:time_spent].to_i
      @progress.save!
    end

    head :ok
  end

  # POST /trainings/:id/complete_training
  # Called by JS when the full required duration has elapsed
  def complete_training
    @training = Training.find(params[:id])
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    @progress.status     = "completed"
    @progress.started_at ||= Time.current
    @progress.ended_at   = Time.current
    @progress.time_spent = params[:time_spent].to_i   # seconds spent (sent from JS)
    @progress.financial_year = financial_year_for(@training.month, @training.year)
    @progress.save!

    render json: {
      status:     @progress.status,
      started_at: @progress.started_at,
      ended_at:   @progress.ended_at,
      time_spent: @progress.time_spent
    }
  end

  # Converts PPT/DOCX to PDF using LibreOffice and streams it for inline preview
  def preview
    @training = Training.find(params[:id])
    # Use find_by for more robust lookup
    file = @training.files.find_by(id: params[:file_id])

    return render plain: "File not found", status: :not_found unless file

    # If it's already a PDF, just redirect
    if file.content_type.include?("pdf")
      redirect_to rails_blob_path(file, disposition: "inline")
      return
    end

    # For PPT/DOCX: download to temp, convert with LibreOffice, stream back
    begin
      tmp_dir = Dir.mktmpdir("training_preview_")
      original_ext = File.extname(file.filename.to_s)
      tmp_input = File.join(tmp_dir, "input#{original_ext}")

      # Write file content to temp location
      File.open(tmp_input, "wb") do |f|
        f.write(file.download)
      end

      # Find libreoffice command (server pe install zaroori: apt install libreoffice-core libreoffice-impress)
      libre_cmd = ENV["LIBREOFFICE_PATH"].presence
      unless libre_cmd.present? && File.exist?(libre_cmd)
        %w[
          /usr/bin/libreoffice
          /usr/bin/soffice
        ].each do |path|
          if File.exist?(path)
            libre_cmd = path
            break
          end
        end
      end
      libre_cmd = `which libreoffice 2>/dev/null`.strip if libre_cmd.blank?
      libre_cmd = `which soffice 2>/dev/null`.strip if libre_cmd.blank?

      if libre_cmd.present? && File.exist?(libre_cmd)
        # Use tmp_dir as the LibreOffice user installation so it works for ANY user
        # (local dev or www-data on server) without needing a writable home dir.
        # Run from /tmp (chdir) to avoid CWD issues with spaces in the app path.
        libre_user_dir = File.join(tmp_dir, "lo_profile")
        FileUtils.mkdir_p(libre_user_dir)

        convert_cmd = [
          libre_cmd,
          "--headless",
          "--convert-to", "pdf",
          "--outdir", tmp_dir,
          "-env:UserInstallation=file://#{libre_user_dir}",
          tmp_input
        ]

        require "open3"
        _stdout, stderr, status = Open3.capture3(
          {
            "HOME"          => tmp_dir,
            "TMPDIR"        => "/tmp",
            "XDG_CACHE_HOME"  => File.join(tmp_dir, ".cache"),
            "XDG_CONFIG_HOME" => File.join(tmp_dir, ".config"),
            "DCONF_PROFILE"   => "0"
          },
          *convert_cmd,
          chdir: "/tmp"
        )

        Rails.logger.info "LibreOffice exit: #{status.exitstatus} | stderr: #{stderr}"

        pdf_path = File.join(tmp_dir, "input.pdf")

        if File.exist?(pdf_path)
          pdf_data = File.read(pdf_path)
          send_data pdf_data,
            type: "application/pdf",
            disposition: "inline",
            filename: "#{File.basename(file.filename.to_s, original_ext)}.pdf"
        else
          render html: "<!DOCTYPE html><html><body style='font-family: sans-serif; padding: 20px; color: #666;'><h3>Preview Unavailable</h3><p>Could not generate a preview for this file type. Please <a href='#{rails_blob_path(file, disposition: 'attachment')}'>download</a> it to view.</p></body></html>".html_safe, status: :ok
        end
      else
        Rails.logger.warn "PPT/DOCX preview: LibreOffice not found. On server run: sudo apt install -y libreoffice-core libreoffice-impress"
        render html: "<!DOCTYPE html><html><body style='font-family: sans-serif; padding: 20px; color: #666;'><h3>Preview Service Unavailable</h3><p>Server-side preview is not available on this server. Install LibreOffice on the server (e.g. <code>sudo apt install -y libreoffice-core libreoffice-impress</code>), then restart the app. Until then, please <a href='#{rails_blob_path(file, disposition: 'attachment')}'>download</a> the file directly.</p></body></html>".html_safe, status: :ok
      end
    rescue StandardError => e
      Rails.logger.error "Preview Conversion Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render html: "<!DOCTYPE html><html><body style='font-family: sans-serif; padding: 20px; color: #666;'><h3>Error</h3><p>An error occurred while generating the preview. Please <a href='#{rails_blob_path(file, disposition: 'attachment')}'>download</a> the file.</p></body></html>".html_safe, status: :ok
    ensure
      if tmp_dir && Dir.exist?(tmp_dir)
        # www-data may have written files in tmp_dir; make them all deletable first
        system("chmod -R 777 #{Shellwords.escape(tmp_dir)} 2>/dev/null")
        FileUtils.remove_entry_secure(tmp_dir)
      end
    end
  end

  def certificate
    @training = Training.find(params[:id])
    @target_user = (current_user.hod? && params[:user_id].present?) ? User.find(params[:user_id]) : current_user
    @progress = UserTrainingProgress.find_by(training: @training, user: @target_user, status: "completed")

    unless @progress
      redirect_to trainings_path, alert: "Certificate not found or training not completed."
      return
    end

    @employee_detail = @target_user.employee_detail || EmployeeDetail.find_by(employee_email: @target_user.email)
    @user_name = @employee_detail&.employee_name || @target_user.email
    @completion_date = @progress.ended_at&.strftime("%d %b %Y") || Time.current.strftime("%d %b %Y")
    @certificate_type = "single"
    @display_title = @training.title

    render_certificate
  end

  def monthly_certificate
    @year  = params[:year].to_i
    @month = params[:month].to_i
    @target_user = (current_user.hod? && params[:user_id].present?) ? User.find(params[:user_id]) : current_user

    employee = @target_user.employee_detail || EmployeeDetail.find_by(employee_email: @target_user.email)

    # 1. Use same set of trainings as index: assigned-only if assignments_managed, else all for this month/year
    if employee&.assignments_managed?
      assigned_ids = employee.user_training_assignments.pluck(:training_id)
      @month_trainings = Training.where(month: @month, year: @year, id: assigned_ids)
    else
      @month_trainings = Training.where(month: @month, year: @year)
    end

    if @month_trainings.empty?
      redirect_to trainings_path, alert: "No active trainings found for this month."
      return
    end

    # 2. Check if ALL are completed AND meet duration requirements
    all_progress = UserTrainingProgress
      .where(user: @target_user, training_id: @month_trainings.pluck(:id))
      .order(
        Arel.sql("CASE WHEN status = 'completed' THEN 0 ELSE 1 END ASC"),
        ended_at: :desc,
        updated_at: :desc,
        id: :desc
      )

    # Map "best" progress for quick check (handles duplicate rows safely)
    progress_map = {}
    all_progress.each do |p|
      progress_map[p.training_id] ||= p
    end

    valid_completions = @month_trainings.all? do |t|
      p = progress_map[t.id]
      # Status must be completed AND time_spent (seconds) >= duration (seconds)
      p&.status == "completed" && (p.time_spent.to_i >= t.duration.to_i)
    end

    unless valid_completions
      redirect_to trainings_path, alert: "Please complete all trainings for #{Date::MONTHNAMES[@month]} #{@year} and spend the required time on each to get the certificate."
      return
    end

    @employee_detail = employee
    @user_name = @employee_detail&.employee_name || @target_user.email
    last_progress = all_progress.order(ended_at: :desc).first
    @completion_date = last_progress&.ended_at&.strftime("%d %b %Y") || Time.current.strftime("%d %b %Y")

    @certificate_type = "monthly"
    @month_name = Date::MONTHNAMES[@month]
    @display_title = "#{@month_name} #{@year} Training Program"

    begin
      render_certificate
    rescue StandardError => e
      Rails.logger.error "PDF certificate failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to trainings_path, alert: "Certificate could not be generated. Please ensure wkhtmltopdf is installed on the server. (Check log for details.)"
    end
  end

  def assessment
    @training = Training.find(params[:id])
    @questions = @training.training_questions
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    # Optional: check if already completed
    if @progress.status == "completed"
      redirect_to trainings_path, notice: "You have already completed this training."
    end
  end

  def download_assessment_template
    respond_to do |format|
      format.xlsx {
        response.headers["Content-Disposition"] = "attachment; filename=Assessment_Template.xlsx"
      }
    end
  end

  def submit_assessment
    @training = Training.find(params[:id])
    @questions = @training.training_questions
    @progress = UserTrainingProgress.find_or_initialize_by(
      training: @training,
      user: current_user
    )

    if @progress.status == "completed"
      redirect_to trainings_path, notice: "You have already completed this training."
      return
    end

    @score = 0
    @total = @questions.count
    @results = []

    if params[:answers].present?
      @questions.each do |q|
        user_answer = params[:answers][q.id.to_s]&.strip
        correct_answer = q.correct_answer&.strip

        # safely handle nil comparison
        is_correct = user_answer.present? && correct_answer.present? && user_answer.downcase == correct_answer.downcase

        if is_correct
          @score += 1
        end

        @results << {
          question: q.question,
          user_answer: user_answer,
          correct_answer: correct_answer,
          is_correct: is_correct
        }
      end
    end

    unless @progress.status == "completed"
      @progress.status     = "completed"
      @progress.started_at ||= Time.current
      @progress.ended_at   = Time.current
      @progress.financial_year = financial_year_for(@training.month, @training.year)
      @progress.score = @score
      @progress.save!
    end

    if @total == 0 || !@training.has_assessment
      redirect_to trainings_path, notice: "Training completed successfully. Your certificate is ready!"
    else
      render :assessment_result
    end
  end

  private

  def render_certificate
    render pdf: "Certificate_#{@display_title}",
           template: "trainings/certificate",
           formats: [ :pdf ],
           layout: "pdf",
           orientation: "Landscape",
           page_size: "A4",
           margin: { top: 0, bottom: 0, left: 0, right: 0 },
           no_background: false,
           print_media_type: true,
           disable_smart_shrinking: true,
           zoom: 1
  end

  private

  def training_params
    params.require(:training)
          .permit(:title, :description, :duration, :month, :year, :status, :has_assessment, files: [],
                 training_questions_attributes: [ :id, :question, :option_a, :option_b, :option_c, :option_d, :correct_answer, :_destroy ])
  end

  def import_questions_from_excel(training, file)
    require "roo"
    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1)

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[ header, spreadsheet.row(i) ].transpose]

      q_text = row.keys.find { |k| k.to_s.downcase.include?("question") } || header[0]
      opt_a = row.keys.find { |k| k.to_s.downcase.include?("option a") || k.to_s.downcase == "a" || k.to_s.downcase == "option_a" } || header[1]
      opt_b = row.keys.find { |k| k.to_s.downcase.include?("option b") || k.to_s.downcase == "b" || k.to_s.downcase == "option_b" } || header[2]
      opt_c = row.keys.find { |k| k.to_s.downcase.include?("option c") || k.to_s.downcase == "c" || k.to_s.downcase == "option_c" } || header[3]
      opt_d = row.keys.find { |k| k.to_s.downcase.include?("option d") || k.to_s.downcase == "d" || k.to_s.downcase == "option_d" } || header[4]
      ans = row.keys.find { |k| k.to_s.downcase.include?("answer") } || header[5]

      next unless row[q_text].present?

      training.training_questions.create(
        question: row[q_text],
        option_a: row[opt_a],
        option_b: row[opt_b],
        option_c: row[opt_c],
        option_d: row[opt_d],
        correct_answer: row[ans]
      )
    end
  rescue StandardError => e
    Rails.logger.error "Excel Import Failed: #{e.message}"
  end

  # Returns financial year string like "2025-26" based on training month & year
  def financial_year_for(month, year)
    month = month.to_i
    year  = year.to_i
    if month >= 4
      "#{year}-#{(year + 1).to_s.last(2)}"
    else
      "#{year - 1}-#{year.to_s.last(2)}"
    end
  end
end
