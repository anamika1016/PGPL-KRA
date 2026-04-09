# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_07_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "achievement_remarks", force: :cascade do |t|
    t.text "l1_remarks"
    t.float "l1_percentage"
    t.text "l2_remarks"
    t.float "l2_percentage"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "employee_remarks"
    t.bigint "achievement_id", null: false
    t.index ["achievement_id"], name: "index_achievement_remarks_on_achievement_id"
  end

  create_table "achievements", force: :cascade do |t|
    t.bigint "user_detail_id", null: false
    t.string "month"
    t.string "achievement"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending"
    t.text "l1_remarks"
    t.float "l1_percentage"
    t.text "l2_remarks"
    t.float "l2_percentage"
    t.text "employee_remarks"
    t.string "financial_year"
    t.index ["financial_year"], name: "index_achievements_on_financial_year"
    t.index ["month"], name: "index_achievements_on_month"
    t.index ["status"], name: "index_achievements_on_status"
    t.index ["user_detail_id", "month"], name: "index_achievements_on_user_detail_id_and_month"
    t.index ["user_detail_id"], name: "index_achievements_on_user_detail_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.bigint "department_id", null: false
    t.integer "activity_id"
    t.string "activity_name"
    t.string "unit"
    t.float "weight"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "theme_name"
    t.string "financial_year"
    t.index ["department_id"], name: "index_activities_on_department_id"
    t.index ["financial_year"], name: "index_activities_on_financial_year"
  end

  create_table "departments", force: :cascade do |t|
    t.string "department_type"
    t.integer "theme_id"
    t.string "theme_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "employee_reference"
    t.string "financial_year"
    t.index ["financial_year"], name: "index_departments_on_financial_year"
  end

  create_table "employee_details", force: :cascade do |t|
    t.string "employee_id"
    t.string "employee_name"
    t.string "employee_email"
    t.string "employee_code"
    t.string "l1_code"
    t.string "l2_code"
    t.string "l1_employer_name"
    t.string "l2_employer_name"
    t.string "post"
    t.string "department"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending"
    t.bigint "user_id"
    t.text "l1_remarks"
    t.float "l1_percentage"
    t.text "l2_remarks"
    t.float "l2_percentage"
    t.string "mobile_number"
    t.boolean "assignments_managed", default: false
    t.index ["user_id"], name: "index_employee_details_on_user_id"
  end

  create_table "l1_pulse_assessments", force: :cascade do |t|
    t.bigint "employee_detail_id", null: false
    t.bigint "l1_user_id", null: false
    t.text "remarks"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "remark_score"
    t.integer "sense_of_purpose"
    t.integer "workload_balance"
    t.integer "manager_effectiveness"
    t.integer "team_collaboration"
    t.integer "recognition_growth"
    t.integer "org_communication"
    t.integer "learning_development"
    t.integer "role_clarity"
    t.integer "work_environment"
    t.integer "commitment_retention"
    t.integer "professionalism_conduct"
    t.integer "work_quality_accuracy"
    t.integer "initiative_problem_solving"
    t.integer "papl_values_culture"
    t.integer "collaboration"
    t.integer "time_management_reliability"
    t.integer "growth_mindset_development"
    t.index ["employee_detail_id", "l1_user_id"], name: "index_l1_pulse_assessments_on_employee_and_l1_user", unique: true
    t.index ["employee_detail_id"], name: "index_l1_pulse_assessments_on_employee_detail_id"
    t.index ["l1_user_id"], name: "index_l1_pulse_assessments_on_l1_user_id"
  end

  create_table "sms_logs", force: :cascade do |t|
    t.string "quarter"
    t.boolean "sent"
    t.datetime "sent_at"
    t.bigint "employee_detail_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_detail_id"], name: "index_sms_logs_on_employee_detail_id"
  end

  create_table "target_submissions", force: :cascade do |t|
    t.bigint "user_detail_id", null: false
    t.bigint "user_id", null: false
    t.bigint "employee_detail_id", null: false
    t.string "month"
    t.string "target"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "financial_year"
    t.index ["employee_detail_id"], name: "index_target_submissions_on_employee_detail_id"
    t.index ["financial_year"], name: "index_target_submissions_on_financial_year"
    t.index ["user_detail_id"], name: "index_target_submissions_on_user_detail_id"
    t.index ["user_id"], name: "index_target_submissions_on_user_id"
  end

  create_table "training_questions", force: :cascade do |t|
    t.bigint "training_id", null: false
    t.text "question"
    t.string "option_a"
    t.string "option_b"
    t.string "option_c"
    t.string "option_d"
    t.string "correct_answer"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["training_id"], name: "index_training_questions_on_training_id"
  end

  create_table "trainings", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.integer "duration"
    t.integer "created_by"
    t.integer "month"
    t.integer "year"
    t.boolean "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "has_assessment"
  end

  create_table "user_details", force: :cascade do |t|
    t.bigint "department_id", null: false
    t.bigint "activity_id", null: false
    t.text "april"
    t.text "may"
    t.text "june"
    t.text "july"
    t.text "august"
    t.text "september"
    t.text "october"
    t.text "november"
    t.text "december"
    t.text "january"
    t.text "february"
    t.text "march"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "employee_detail_id"
    t.bigint "user_id"
    t.string "financial_year", null: false
    t.string "theme_name"
    t.string "unit"
    t.index ["activity_id"], name: "index_user_details_on_activity_id"
    t.index ["department_id", "activity_id", "employee_detail_id", "financial_year"], name: "index_user_details_on_department_activity_employee_fy"
    t.index ["department_id"], name: "index_user_details_on_department_id"
    t.index ["employee_detail_id", "financial_year"], name: "index_user_details_on_employee_detail_id_and_financial_year"
    t.index ["employee_detail_id"], name: "index_user_details_on_employee_detail_id"
    t.index ["financial_year"], name: "index_user_details_on_financial_year"
    t.index ["user_id"], name: "index_user_details_on_user_id"
  end

  create_table "user_training_assignments", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "training_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "employee_detail_id"
    t.index ["employee_detail_id", "training_id"], name: "index_uta_on_employee_detail_and_training", unique: true
    t.index ["employee_detail_id"], name: "index_user_training_assignments_on_employee_detail_id"
    t.index ["training_id"], name: "index_user_training_assignments_on_training_id"
    t.index ["user_id"], name: "index_user_training_assignments_on_user_id"
  end

  create_table "user_training_progresses", force: :cascade do |t|
    t.bigint "training_id", null: false
    t.bigint "user_id", null: false
    t.string "status"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.integer "time_spent"
    t.string "financial_year"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "score"
    t.index ["training_id"], name: "index_user_training_progresses_on_training_id"
    t.index ["user_id"], name: "index_user_training_progresses_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role"
    t.string "employee_code"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "achievement_remarks", "achievements"
  add_foreign_key "achievements", "user_details"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "departments"
  add_foreign_key "employee_details", "users"
  add_foreign_key "l1_pulse_assessments", "employee_details"
  add_foreign_key "l1_pulse_assessments", "users", column: "l1_user_id"
  add_foreign_key "sms_logs", "employee_details"
  add_foreign_key "target_submissions", "employee_details"
  add_foreign_key "target_submissions", "user_details"
  add_foreign_key "target_submissions", "users"
  add_foreign_key "training_questions", "trainings"
  add_foreign_key "user_details", "activities"
  add_foreign_key "user_details", "departments"
  add_foreign_key "user_details", "employee_details"
  add_foreign_key "user_details", "users"
  add_foreign_key "user_training_assignments", "employee_details"
  add_foreign_key "user_training_assignments", "trainings"
  add_foreign_key "user_training_assignments", "users"
  add_foreign_key "user_training_progresses", "trainings"
  add_foreign_key "user_training_progresses", "users"
end
