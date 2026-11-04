require "test_helper"

class Oauth::AuthorizationServerTest < ActionDispatch::IntegrationTest
  setup do
    @client = create_public_client
    @verifier, @challenge = pkce_pair
  end

  # --- Discovery ------------------------------------------------------------------------

  test "publishes the metadata MCP clients rely on" do
    get "/.well-known/oauth-authorization-server"

    assert_response :success
    metadata = response.parsed_body
    assert_equal "http://localhost:3000", metadata["issuer"]
    assert_equal "http://localhost:3000/oauth/authorize", metadata["authorization_endpoint"]
    assert_equal "http://localhost:3000/oauth/token", metadata["token_endpoint"]
    assert_equal "http://localhost:3000/oauth/register", metadata["registration_endpoint"]
    assert_equal "http://localhost:3000/oauth/revoke", metadata["revocation_endpoint"]
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_equal [ "code" ], metadata["response_types_supported"]
    assert_equal [ "query" ], metadata["response_modes_supported"]
    assert_equal %w[ authorization_code refresh_token ].sort, metadata["grant_types_supported"].sort
    assert_equal %w[ client_secret_basic none ].sort, metadata["token_endpoint_auth_methods_supported"].sort
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, metadata["scopes_supported"].sort
    assert_equal true, metadata["authorization_response_iss_parameter_supported"]
    assert_equal true, metadata["client_id_metadata_document_supported"]
    assert_not metadata.key?("introspection_endpoint")
  end

  test "exposes neither the admin UI nor the token info and introspection endpoints" do
    [ [ :get, "/oauth/applications" ], [ :get, "/oauth/authorized_applications" ],
      [ :get, "/oauth/token/info" ], [ :post, "/oauth/introspect" ] ].each do |verb, path|
      public_send(verb, path)
      assert_response :not_found, "#{verb} #{path}"
    end
  end

  # --- The authorization code flow ------------------------------------------------------

  test "the whole flow: login, consent, code, token bound to the resource" do
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
    assert_redirected_to "/oauth/login"

    sign_in
    assert_response :see_other
    assert_includes response.location, "/oauth/authorize?"

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Test client"
    assert_includes response.body, "127.0.0.1"
    assert_includes response.body, "program running on this computer"
    assert_includes response.body, "registered itself"
    assert_includes response.body, "Read posts"
    assert_includes response.body, Oauth::ResourceIndicator.canonical

    post "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
    assert_response :redirect
    assert response.location.start_with?(@client.redirect_uri)
    assert_equal "state-123", redirect_query["state"]
    assert_equal "http://localhost:3000", redirect_query["iss"]

    exchange_code(@client, code: redirect_query["code"], verifier: @verifier)
    assert_response :success
    tokens = response.parsed_body
    assert_equal "Bearer", tokens["token_type"]
    assert_equal 1.hour.to_i, tokens["expires_in"]
    assert tokens["refresh_token"]

    access_token = Doorkeeper::AccessToken.by_token(tokens["access_token"])
    assert_equal Oauth::ResourceIndicator.canonical, access_token.resource
    assert_equal users(:alice).id, access_token.resource_owner_id
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, access_token.scopes.to_a.sort
  end

  test "denying returns access_denied to the client with the issuer" do
    sign_in
    delete "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)

    assert_response :redirect
    assert_equal "access_denied", redirect_query["error"]
    assert_equal "http://localhost:3000", redirect_query["iss"]
    assert_equal "state-123", redirect_query["state"]
  end

  test "a client that asks for no scope gets one consent for every scope" do
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, obtain_tokens(@client, scope: nil)["scope"].split.sort
  end

  test "a client that asks for a few scopes sees and gets all of them" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge, scope: "posts:read posts:write posts:delete")

    assert_response :success
    Doorkeeper.configuration.scopes.each do |scope|
      assert_includes response.body, I18n.t("doorkeeper.scopes.#{scope}"), scope
    end
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, obtain_tokens(@client, scope: "posts:read")["scope"].split.sort
  end

  test "an unknown scope is refused" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge, scope: "posts:read admin")

    assert_response :redirect
    assert_equal "invalid_scope", redirect_query["error"]
  end

  # --- PKCE -----------------------------------------------------------------------------

  test "a request without a code challenge is refused" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: nil)

    assert_response :redirect
    assert_equal "invalid_request", redirect_query["error"]
  end

  test "the plain challenge method is refused" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @verifier, code_challenge_method: "plain")

    assert_response :redirect
    assert_equal "invalid_code_challenge_method", redirect_query["error"]
  end

  test "the code cannot be exchanged without the right verifier" do
    code = obtain_authorization_code(@client, challenge: @challenge)

    exchange_code(@client, code:, verifier: nil)
    assert_response :bad_request

    exchange_code(@client, code:, verifier: pkce_pair.first)
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  # --- Redirect URIs --------------------------------------------------------------------

  test "the redirect URI must match exactly and is never redirected to otherwise" do
    https_client = create_public_client(redirect_uri: "https://app.example.com/callback")
    sign_in

    [ "https://evil.example/callback", "https://app.example.com/callback/extra",
      "https://app.example.com/callback?injected=1" ].each do |redirect_uri|
      get "/oauth/authorize", params: authorization_params(https_client, challenge: @challenge, redirect_uri:)

      assert_response :bad_request, redirect_uri
      assert_nil response.location
    end
  end

  test "a loopback redirect URI may use any port" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge, redirect_uri: "http://127.0.0.1:50000/callback")

    assert_response :success
  end

  test "an unknown client is refused before anyone is asked to log in" do
    get "/oauth/authorize", params: { response_type: "code", client_id: "unknown", redirect_uri: "https://evil.example/cb" }

    assert_response :unauthorized
    assert_includes response.body, "cannot continue"
    assert_nil response.location
  end

  # --- Audience binding -----------------------------------------------------------------

  test "a token for another resource is refused with invalid_target" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge, resource: "https://other.example/mcp")

    assert_response :redirect
    assert_equal "invalid_target", redirect_query["error"]
    assert_equal "http://localhost:3000", redirect_query["iss"]
  end

  test "a client that sends no resource still gets a token bound to the MCP endpoint" do
    tokens = obtain_tokens(@client, resource: nil)

    assert_equal Oauth::ResourceIndicator.canonical, Doorkeeper::AccessToken.by_token(tokens["access_token"]).resource
  end

  test "the token request cannot widen the audience of the grant" do
    code = obtain_authorization_code(@client, challenge: @challenge)

    exchange_code(@client, code:, verifier: @verifier, resource: "https://other.example/mcp")

    assert_response :bad_request
    assert_equal "invalid_target", response.parsed_body["error"]
  end

  # --- Token lifecycle ------------------------------------------------------------------

  test "a code works once, and a replay revokes what it issued" do
    code = obtain_authorization_code(@client, challenge: @challenge)
    exchange_code(@client, code:, verifier: @verifier)
    access_token = response.parsed_body["access_token"]

    exchange_code(@client, code:, verifier: @verifier)

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert_predicate Doorkeeper::AccessToken.by_token(access_token), :revoked?
  end

  test "an expired code is refused" do
    code = obtain_authorization_code(@client, challenge: @challenge)

    travel 6.minutes do
      exchange_code(@client, code:, verifier: @verifier)
    end

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "refresh tokens rotate, and the new token keeps scope and audience" do
    first = obtain_tokens(@client)

    refresh(@client, first["refresh_token"])
    assert_response :success
    second = response.parsed_body
    assert_not_equal first["refresh_token"], second["refresh_token"]

    renewed = Doorkeeper::AccessToken.by_token(second["access_token"])
    assert_equal Oauth::ResourceIndicator.canonical, renewed.resource
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, renewed.scopes.to_a.sort

    refresh(@client, first["refresh_token"])
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "a refresh token only works for the client it was issued to" do
    tokens = obtain_tokens(@client)

    refresh(create_public_client, tokens["refresh_token"])

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "tokens can be revoked" do
    tokens = obtain_tokens(@client)

    post "/oauth/revoke", params: { token: tokens["access_token"], client_id: @client.uid }

    assert_response :success
    assert_predicate Doorkeeper::AccessToken.by_token(tokens["access_token"]), :revoked?
  end

  test "credentials are stored only as digests" do
    tokens = obtain_tokens(@client)

    assert_not Doorkeeper::AccessToken.exists?(token: tokens["access_token"])
    assert_not Doorkeeper::AccessToken.exists?(refresh_token: tokens["refresh_token"])
    assert Doorkeeper::AccessToken.exists?(token: Digest::SHA256.hexdigest(tokens["access_token"]))
  end

  # --- The forms a browser actually submits -----------------------------------------------
  #
  # API-only Rails has no Rack::MethodOverride: a form relying on `_method` would be routed by
  # its POST. On the consent page that once meant "Deny" granted access. So these tests submit
  # what the page renders, the way a browser does, never an assumed route.

  test "the Allow button on the rendered consent page grants access" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)

    submit_form_with_button("Allow")

    assert_response :redirect
    assert redirect_query["code"].present?
    assert_nil redirect_query["error"]
  end

  test "the Deny button on the rendered consent page denies access" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)

    assert_no_difference("Doorkeeper::AccessGrant.count") do
      submit_form_with_button("Deny")
    end

    assert_response :redirect
    assert_equal "access_denied", redirect_query["error"]
    assert_nil redirect_query["code"]
    assert_equal "http://localhost:3000", redirect_query["iss"]
  end

  test "the sign out button on the rendered consent page signs out" do
    sign_in
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)

    submit_form_with_button("Use another account")

    assert_response :see_other
    assert_nil session[:user_id]
  end

  # A browser posts `Origin: null` from a page sent with `Referrer-Policy: no-referrer`, and Rails
  # refuses that. Sign-in once failed for every real browser this way, with this suite green, as it
  # had CSRF protection off and sent no Origin. So: protection on, Origin as a browser derives it.

  test "a browser signs in and approves a client, with CSRF protection on" do
    with_forgery_protection do
      get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
      follow_redirect!

      submit_form_with_button("Sign in", email_address: users(:alice).email_address, password: PASSWORD)
      assert_response :see_other, "sign-in was refused: #{response.body[0, 300]}"
      follow_redirect!

      submit_form_with_button("Allow")
      assert_response :redirect
      assert redirect_query["code"].present?, response.location
    end
  end

  test "a browser denies a client and signs out, with CSRF protection on" do
    with_forgery_protection do
      get "/oauth/login"
      submit_form_with_button("Sign in", email_address: users(:alice).email_address, password: PASSWORD)

      get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
      submit_form_with_button("Deny")
      assert_equal "access_denied", redirect_query["error"]

      get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
      submit_form_with_button("Use another account")
      assert_response :see_other
      assert_nil session[:user_id]
    end
  end

  test "a sign-in posted from another site is refused, even with a valid token" do
    with_forgery_protection do
      get "/oauth/login"

      submit_form_with_button("Sign in", origin: "https://evil.example", email_address: users(:alice).email_address, password: PASSWORD)

      assert_response :unprocessable_content
      assert_nil session[:user_id]
    end
  end

  test "the icon every browser asks for is answered, not a routing error" do
    get "/favicon.ico"

    assert_response :no_content
  end

  test "no page relies on a method override, which this stack does not have" do
    get "/oauth/login"
    assert_empty css_select("input[name=_method]")

    sign_in
    get "/oauth/login"
    assert_empty css_select("input[name=_method]")

    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)
    assert_empty css_select("input[name=_method]")
    assert_not_includes Rails.application.middleware.map(&:name), "Rack::MethodOverride"
  end

  # --- Browser pages --------------------------------------------------------------------

  test "wrong credentials do not sign in" do
    post "/oauth/login", params: { email_address: users(:alice).email_address, password: "wrong" }

    assert_response :unprocessable_content
    assert_includes response.body, "Incorrect email address or password."
    assert_nil session[:user_id]
  end

  test "malformed credentials do not raise" do
    post "/oauth/login", params: { email_address: { a: 1 }, password: [ "x" ] }

    assert_response :unprocessable_content
  end

  test "login replaces the session and signing out ends it" do
    get "/oauth/login"
    id_before = session.id.to_s

    sign_in
    assert_equal users(:alice).id, session[:user_id]
    assert_not_equal id_before, session.id.to_s

    post "/oauth/logout"
    assert_nil session[:user_id]
  end

  test "pages carry the hardening headers" do
    get "/oauth/login"

    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'none'"
    assert_includes response.headers["Content-Security-Policy"], "default-src 'none'"
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "the session cookie stays on the OAuth pages" do
    sign_in

    cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/_mcp_oauth_session=/, cookie)
    assert_match(%r{path=/oauth}i, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
  end

  test "consent cannot be forged cross-site" do
    with_forgery_protection do
      sign_in_with_real_token
      post "/oauth/authorize", params: authorization_params(@client, challenge: @challenge)

      assert_response :unprocessable_content
      assert_nil response.location
    end
  end

  test "an oversized authorization request does not overflow the session cookie" do
    get "/oauth/authorize", params: authorization_params(@client, challenge: @challenge, state: "x" * 5000)

    assert_response :uri_too_long
  end

  private

  # Submits the rendered form the way a browser does: its hidden fields, what the person typed, and
  # the Origin header the current page's Referrer-Policy produces (Fetch standard, "serializing a
  # request origin": a no-referrer page posts `Origin: null`).
  def submit_form_with_button(label, origin: nil, **typed)
    origin ||= response.headers["Referrer-Policy"] == "no-referrer" ? "null" : request.base_url
    form = css_select("form").find { |candidate| candidate.css("input[type=submit],button").any? { |button| [ button["value"], button.text ].include?(label) } }
    assert form, "no form with a #{label.inspect} button in: #{response.body}"
    assert_equal "post", form["method"].to_s.downcase

    fields = form.css("input[type=hidden]").each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |input, all| all[input["name"]] << input["value"].to_s }
    params = fields.to_h { |name, values| name.end_with?("[]") ? [ name.delete_suffix("[]"), values ] : [ name, values.last ] }
    post form["action"], params: params.merge(typed), headers: { "Origin" => origin }
  end

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def sign_in_with_real_token
    get "/oauth/login"
    token = response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    post "/oauth/login", params: { email_address: users(:alice).email_address, password: PASSWORD, authenticity_token: token }
    assert_response :see_other
  end
end
