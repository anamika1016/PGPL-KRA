class Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, only: [ :create ] # only for testing, enable CSRF later

  def create
    submitted_email = params[:user][:email]
    submitted_password = params[:user][:password]
    # submitted_role = params[:user][:role]
    submitted_code = params[:user][:employee_code]&.strip

    user = User.find_by(email: submitted_email)

    if user.nil?
      flash[:alert] = "No account found with that email."
      redirect_to new_session_path(resource_name) and return
    end

    unless user.valid_password?(submitted_password)
      flash[:alert] = "Incorrect password."
      redirect_to new_session_path(resource_name) and return
    end

    unless user.employee_code == submitted_code
      flash[:alert] = "Incorrect employee code."
      redirect_to new_session_path(resource_name) and return
    end

    sign_in(resource_name, user)
    redirect_to after_sign_in_path_for(user)
  end
end
