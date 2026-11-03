# Drives the OAuth flow the way an MCP client does, so tests assert the public contract.
module OauthTestHelpers
  PASSWORD = "correct horse battery staple".freeze
  LOOPBACK_REDIRECT_URI = "http://127.0.0.1:33418/callback".freeze

  def create_public_client(redirect_uri: LOOPBACK_REDIRECT_URI, registration_type: "dynamic", name: "Test client")
    Doorkeeper::Application.create!(name:, redirect_uri:, confidential: false, registration_type:)
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(48)
    [ verifier, Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) ]
  end

  def authorization_params(client, challenge:, **overrides)
    {
      response_type: "code",
      client_id: client.uid,
      redirect_uri: client.redirect_uri.split.first,
      scope: "posts:read",
      state: "state-123",
      code_challenge: challenge,
      code_challenge_method: "S256",
      resource: Oauth::ResourceIndicator.canonical
    }.merge(overrides).compact
  end

  def sign_in(user = users(:alice))
    post "/oauth/login", params: { email_address: user.email_address, password: PASSWORD }
  end

  def redirect_query
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  # Login plus a click on "Allow". Returns the authorization code from the redirect.
  def obtain_authorization_code(client, challenge:, **overrides)
    sign_in
    post "/oauth/authorize", params: authorization_params(client, challenge:, **overrides)
    redirect_query.fetch("code")
  end

  def exchange_code(client, code:, verifier:, **overrides)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code:,
      client_id: client.uid,
      redirect_uri: client.redirect_uri.split.first,
      code_verifier: verifier,
      resource: Oauth::ResourceIndicator.canonical
    }.merge(overrides).compact
  end

  def refresh(client, refresh_token, **overrides)
    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token:,
      client_id: client.uid,
      resource: Oauth::ResourceIndicator.canonical
    }.merge(overrides).compact
  end

  # The complete grant, returning the parsed token response.
  def obtain_tokens(client = create_public_client, **overrides)
    verifier, challenge = pkce_pair
    code = obtain_authorization_code(client, challenge:, **overrides)
    exchange_code(client, code:, verifier:)
    response.parsed_body
  end

  # Replaces an instance method for the duration of the block. minitest 6 has no stubbing.
  def stub_instance_method(klass, name, implementation)
    was_private = klass.private_method_defined?(name)
    original = klass.instance_method(name)
    klass.define_method(name, &implementation)
    yield
  ensure
    klass.define_method(name, original)
    klass.send(:private, name) if was_private
  end
end
