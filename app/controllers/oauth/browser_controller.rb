module Oauth
  # Base of every OAuth page a person sees, including Doorkeeper's own controllers
  # (`base_controller` in the Doorkeeper initializer). The app is API-only, so anything a
  # browser needs is opted into here and stays out of the API controllers.
  class BrowserController < ActionController::Base
    # `form-action` is left out on purpose: browsers apply it to the redirect that follows
    # the consent form, and that redirect has to reach the client's own redirect URI.
    CONTENT_SECURITY_POLICY = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'".freeze

    # The URL to resume after login is kept in the session cookie, which is limited to 4 KB.
    MAX_RETURN_TO_BYTES = 2.kilobytes

    protect_from_forgery with: :exception

    layout "oauth"

    before_action :set_security_headers

    helper_method :current_user

    private

    def current_user
      return @current_user if defined?(@current_user)

      @current_user = User.find_by(id: session[:user_id])
    end

    def authenticate_user_or_redirect_to_login
      return current_user if current_user

      if request.fullpath.bytesize > MAX_RETURN_TO_BYTES
        head :uri_too_long
      else
        session[:return_to] = request.fullpath
        redirect_to oauth_login_path
      end
      nil
    end

    # same-origin keeps the authorization URL, with its state and PKCE challenge, away from other
    # sites. It cannot be no-referrer: from such a page a browser posts its forms with
    # `Origin: null`, which Rails' CSRF check refuses, and nobody could sign in.
    def set_security_headers
      response.headers["Content-Security-Policy"] = CONTENT_SECURITY_POLICY
      response.headers["Referrer-Policy"] = "same-origin"
      response.headers["Cache-Control"] = "no-store"
    end
  end
end
