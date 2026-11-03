require "test_helper"

class Oauth::ClientRegistrationTest < ActionDispatch::IntegrationTest
  test "registers a public client" do
    assert_difference("Doorkeeper::Application.count") do
      post "/oauth/register", params: { client_name: "My client", redirect_uris: [ "http://localhost:4000/cb", "https://app.example.com/cb" ] }, as: :json
    end

    assert_response :created
    assert_equal "no-store", response.headers["Cache-Control"]

    body = response.parsed_body
    assert body["client_id"].present?
    assert_equal "My client", body["client_name"]
    assert_equal [ "http://localhost:4000/cb", "https://app.example.com/cb" ], body["redirect_uris"]
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal %w[ authorization_code refresh_token ], body["grant_types"]
    assert_not body.key?("client_secret")

    application = Doorkeeper::Application.by_uid(body["client_id"])
    assert_equal false, application.confidential
    assert_equal "dynamic", application.registration_type
    assert_nil application.read_attribute(:secret)
  end

  test "never creates a confidential client, whatever was asked for" do
    post "/oauth/register", params: { redirect_uris: [ "https://app.example.com/cb" ], token_endpoint_auth_method: "client_secret_post", confidential: true, scopes: "admin" }, as: :json

    assert_response :created
    assert_equal "none", response.parsed_body["token_endpoint_auth_method"]
    assert_not response.parsed_body.key?("client_secret")

    application = Doorkeeper::Application.by_uid(response.parsed_body["client_id"])
    assert_equal false, application.confidential
    assert_empty application.scopes.to_a
  end

  test "names a nameless client" do
    post "/oauth/register", params: { redirect_uris: [ "https://app.example.com/cb" ] }, as: :json

    assert_equal Oauth::RegisterClient::DEFAULT_NAME, response.parsed_body["client_name"]
  end

  test "refuses unacceptable redirect URIs" do
    [
      [],
      [ "http://app.example.com/cb" ],
      [ "javascript:alert(1)" ],
      [ "https://app.example.com/cb#fragment" ],
      [ "custom-scheme://cb" ],
      Array.new(Oauth::RegisterClient::MAX_REDIRECT_URIS + 1) { |i| "https://app.example.com/#{i}" }
    ].each do |redirect_uris|
      assert_no_difference("Doorkeeper::Application.count") do
        post "/oauth/register", params: { redirect_uris: }, as: :json
      end

      assert_response :bad_request
      assert_equal "invalid_redirect_uri", response.parsed_body["error"], redirect_uris.inspect
    end
  end

  test "refuses malformed metadata" do
    post "/oauth/register", params: { redirect_uris: "https://app.example.com/cb" }, as: :json
    assert_response :bad_request
    assert_equal "invalid_redirect_uri", response.parsed_body["error"]

    post "/oauth/register", params: { client_name: "x" * 201, redirect_uris: [ "https://app.example.com/cb" ] }, as: :json
    assert_response :bad_request
    assert_equal "invalid_client_metadata", response.parsed_body["error"]
  end

  test "a registered client can complete the flow" do
    post "/oauth/register", params: { client_name: "My client", redirect_uris: [ OauthTestHelpers::LOOPBACK_REDIRECT_URI ] }, as: :json
    client = Doorkeeper::Application.by_uid(response.parsed_body["client_id"])

    assert obtain_tokens(client)["access_token"]
  end
end
