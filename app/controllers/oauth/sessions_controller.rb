module Oauth
  # Resource owner login. Accounts are created out of band: this sample has no sign-up.
  class SessionsController < BrowserController
    def new
    end

    def create
      user = User.authenticate_by(email_address: params[:email_address].to_s, password: params[:password].to_s)

      if user
        return_to = session[:return_to]
        reset_session # A new session id on every login prevents session fixation.
        session[:user_id] = user.id
        redirect_to return_to.presence || oauth_login_path, status: :see_other
      else
        @error = "Incorrect email address or password."
        render :new, status: :unprocessable_content
      end
    end

    def destroy
      reset_session
      redirect_to oauth_login_path, status: :see_other
    end
  end
end
