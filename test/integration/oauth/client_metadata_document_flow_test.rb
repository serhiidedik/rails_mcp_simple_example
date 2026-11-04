require "test_helper"

class Oauth::ClientMetadataDocumentFlowTest < ActionDispatch::IntegrationTest
  Fetcher = Oauth::FetchClientMetadataDocument
  URL = "https://app.example.com/oauth/client.json".freeze
  REDIRECT_URI = "https://app.example.com/cb".freeze

  def serving(body)
    stub_instance_method(Fetcher, :resolve, ->(_hostname) { [ "93.184.216.34" ] }) do
      stub_instance_method(Fetcher, :read_body, ->(_uri, _address) { body }) { yield }
    end
  end

  def authorize_params(**overrides)
    _verifier, challenge = pkce_pair
    {
      response_type: "code", client_id: URL, redirect_uri: REDIRECT_URI, scope: "posts:read", state: "s",
      code_challenge: challenge, code_challenge_method: "S256", resource: Oauth::ResourceIndicator.canonical
    }.merge(overrides)
  end

  test "a URL client id reaches the consent page, showing where its identity comes from" do
    sign_in

    serving({ client_id: URL, client_name: "Hosted app", redirect_uris: [ REDIRECT_URI ] }.to_json) do
      get "/oauth/authorize", params: authorize_params
    end

    assert_response :success
    assert_includes response.body, "Hosted app"
    assert_includes response.body, "Client identity published at"
    assert_includes response.body, URL
    assert_includes response.body, "app.example.com"
    assert_not_includes response.body, "registered itself"
  end

  test "a redirect URI outside the document is refused and not redirected to" do
    serving({ client_id: URL, client_name: "Hosted app", redirect_uris: [ REDIRECT_URI ] }.to_json) do
      get "/oauth/authorize", params: authorize_params(redirect_uri: "https://evil.example/cb")
    end

    assert_response :bad_request
    assert_nil response.location
  end

  # What a native client serves at its client_id, and how it redirects: the document names
  # no port, and each run listens on a random one.
  NATIVE_CLIENT_URL = "https://client.example/oauth/native-client-metadata".freeze
  NATIVE_CLIENT_DOCUMENT = {
    client_id: NATIVE_CLIENT_URL, client_name: "Native Client", client_uri: "https://client.example",
    redirect_uris: [ "http://localhost/callback", "http://127.0.0.1/callback" ],
    grant_types: %w[ authorization_code refresh_token ], response_types: %w[ code ], token_endpoint_auth_method: "none"
  }.to_json.freeze

  [ "http://localhost:53764/callback", "http://127.0.0.1:53764/callback" ].each do |redirect_uri|
    test "a client whose document names no port signs in through #{redirect_uri}" do
      sign_in
      verifier, challenge = pkce_pair
      params = authorize_params(client_id: NATIVE_CLIENT_URL, redirect_uri:, code_challenge: challenge)

      serving(NATIVE_CLIENT_DOCUMENT) do
        get "/oauth/authorize", params: params
        assert_response :success
        assert_includes response.body, "Native Client"

        post "/oauth/authorize", params: params
      end
      assert response.location.start_with?("#{redirect_uri}?"), response.location

      exchange_code(Doorkeeper::Application.find_by!(uid: NATIVE_CLIENT_URL), code: redirect_query.fetch("code"), verifier:, redirect_uri:)
      assert_response :success
      assert response.parsed_body["access_token"].present?
    end
  end

  [
    "http://localhost:53764/other",
    "https://localhost:53764/callback",
    "http://user@localhost:53764/callback",
    "http://localhost.evil.example:53764/callback",
    "http://evil.example:53764/callback"
  ].each do |redirect_uri|
    test "a loopback port may vary, but nothing else: #{redirect_uri} is refused" do
      serving(NATIVE_CLIENT_DOCUMENT) do
        get "/oauth/authorize", params: authorize_params(client_id: NATIVE_CLIENT_URL, redirect_uri:)
      end

      assert_response :bad_request
      assert_nil response.location
    end
  end

  test "a port only varies on loopback: a registered https redirect still matches exactly" do
    serving({ client_id: URL, client_name: "Hosted app", redirect_uris: [ REDIRECT_URI ] }.to_json) do
      get "/oauth/authorize", params: authorize_params(redirect_uri: "https://app.example.com:8443/cb")
    end

    assert_response :bad_request
  end

  test "an invalid document stops the flow before anyone is asked to log in" do
    serving("not json") do
      get "/oauth/authorize", params: authorize_params
    end

    assert_response :unauthorized
    assert_includes response.body, "cannot continue"
    assert_nil response.location
    assert_not Doorkeeper::Application.exists?(uid: URL)
  end
end
