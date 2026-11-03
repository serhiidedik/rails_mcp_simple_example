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
