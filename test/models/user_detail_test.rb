require "test_helper"

class UserDetailTest < ActiveSupport::TestCase
  test "is valid when employee matches the department reference" do
    employee = EmployeeDetail.create!(
      employee_id: "EMP-IT-1",
      employee_code: "PAPL126",
      employee_name: "Anamika Vishwakarma",
      employee_email: "anamika@example.com",
      department: "IT"
    )
    department = Department.create!(
      department_type: "IT",
      employee_reference: employee.employee_id,
      financial_year: "2026-27"
    )
    activity = Activity.create!(
      department: department,
      activity_name: "Loan Sourcing & Disbursement",
      theme_name: "Loan Origination Process",
      unit: "%",
      weight: 100,
      financial_year: "2026-27"
    )

    user_detail = UserDetail.new(
      department: department,
      activity: activity,
      employee_detail: employee,
      financial_year: "2026-27"
    )

    assert user_detail.valid?
  end

  test "rejects a user detail when the department belongs to another employee" do
    employee = EmployeeDetail.create!(
      employee_id: "EMP-IT-2",
      employee_code: "PAPL126",
      employee_name: "Anamika Vishwakarma",
      employee_email: "anamika-mismatch@example.com",
      department: "IT"
    )
    other_employee = EmployeeDetail.create!(
      employee_code: "PAPL095",
      employee_name: "Ashis Mondal",
      employee_email: "ashis@example.com",
      department: "COO"
    )
    department = Department.create!(
      department_type: "COO",
      employee_reference: other_employee.employee_code,
      financial_year: "2026-27"
    )
    activity = Activity.create!(
      department: department,
      activity_name: "Loan Sourcing & Disbursement",
      theme_name: "Loan Origination Process",
      unit: "%",
      weight: 100,
      financial_year: "2026-27"
    )

    user_detail = UserDetail.new(
      department: department,
      activity: activity,
      employee_detail: employee,
      financial_year: "2026-27"
    )

    assert_not user_detail.valid?
    assert_includes user_detail.errors[:employee_detail_id], "does not belong to the selected department"
  end

  test "assignment_consistent excludes legacy mismatched records" do
    employee = EmployeeDetail.create!(
      employee_id: "EMP-IT-3",
      employee_code: "PAPL126",
      employee_name: "Anamika Vishwakarma",
      employee_email: "anamika-scope@example.com",
      department: "IT"
    )
    other_employee = EmployeeDetail.create!(
      employee_code: "PAPL095",
      employee_name: "Ashis Mondal",
      employee_email: "ashis-scope@example.com",
      department: "COO"
    )
    valid_department = Department.create!(
      department_type: "IT",
      employee_reference: employee.employee_id,
      financial_year: "2026-27"
    )
    invalid_department = Department.create!(
      department_type: "COO",
      employee_reference: other_employee.employee_code,
      financial_year: "2026-27"
    )
    valid_activity = Activity.create!(
      department: valid_department,
      activity_name: "Disbursement",
      theme_name: "Technical Support",
      unit: "%",
      weight: 100,
      financial_year: "2026-27"
    )
    invalid_activity = Activity.create!(
      department: invalid_department,
      activity_name: "Loan Sourcing & Disbursement",
      theme_name: "Loan Origination Process",
      unit: "%",
      weight: 100,
      financial_year: "2026-27"
    )

    valid_detail = UserDetail.create!(
      department: valid_department,
      activity: valid_activity,
      employee_detail: employee,
      financial_year: "2026-27"
    )

    invalid_detail = UserDetail.new(
      department: invalid_department,
      activity: invalid_activity,
      employee_detail: employee,
      financial_year: "2026-27"
    )
    invalid_detail.save!(validate: false)

    consistent_ids = UserDetail.assignment_consistent.where(id: [ valid_detail.id, invalid_detail.id ]).pluck(:id)

    assert_includes consistent_ids, valid_detail.id
    assert_not_includes consistent_ids, invalid_detail.id
  end

  test "assignment_consistent includes generic departments without employee reference" do
    employee = EmployeeDetail.create!(
      employee_id: "EMP-PROJ-1",
      employee_code: "PAPL777",
      employee_name: "Deepak Singh",
      employee_email: "deepak-generic@example.com",
      department: "Project"
    )
    department = Department.create!(
      department_type: "Project",
      employee_reference: "",
      financial_year: "2026-27"
    )
    activity = Activity.create!(
      department: department,
      activity_name: "Village Intro Meeting",
      theme_name: "Village Intro Meeting",
      unit: "No.",
      weight: 100,
      financial_year: "2026-27"
    )

    user_detail = UserDetail.create!(
      department: department,
      activity: activity,
      employee_detail: employee,
      financial_year: "2026-27"
    )

    consistent_ids = UserDetail.assignment_consistent.where(id: user_detail.id).pluck(:id)

    assert_includes consistent_ids, user_detail.id
  end
end
