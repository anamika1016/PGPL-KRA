class Users::PasswordsController < Devise::PasswordsController
  def create
    self.resource = resource_class.find_by(email: resource_params[:email])

    if resource
      token = set_reset_password_token(resource)
      redirect_to edit_user_password_path(reset_password_token: token)
    else
      flash.now[:alert] = "Email not found"
      render :new
    end
  end

  private

  def set_reset_password_token(user)
    raw, enc = Devise.token_generator.generate(User, :reset_password_token)
    user.reset_password_token   = enc
    user.reset_password_sent_at = Time.now.utc
    user.save(validate: false)
    raw
  end
end
