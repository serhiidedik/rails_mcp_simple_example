require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    freeze_time # A counter window must not roll over in the middle of a test.
  end

  teardown do
    Rack::Attack.reset!
    Rack::Attack.enabled = false
  end

  test "password guessing from one address is limited" do
    10.times { post "/oauth/login", params: { email_address: "user#{rand(1000)}@example.com", password: "wrong" } }
    assert_response :unprocessable_content

    post "/oauth/login", params: { email_address: "someone@example.com", password: "wrong" }

    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "rate_limited", response.parsed_body["error"]
  end

  test "password guessing against one account is limited across addresses" do
    10.times do |i|
      post "/oauth/login", params: { email_address: " Alice@Example.com ", password: "wrong" }, headers: { "REMOTE_ADDR" => "203.0.113.#{i}" }
      assert_response :unprocessable_content
    end

    post "/oauth/login", params: { email_address: "alice@example.com", password: "wrong" }, headers: { "REMOTE_ADDR" => "203.0.113.200" }

    assert_response :too_many_requests
  end

  test "the token endpoint is limited" do
    30.times { post "/oauth/token", params: { grant_type: "authorization_code", code: "guess" } }

    post "/oauth/token", params: { grant_type: "authorization_code", code: "guess" }

    assert_response :too_many_requests
  end

  test "client registration is limited" do
    10.times { post "/oauth/register", params: { redirect_uris: [ "https://app.example.com/cb" ] }, as: :json }
    assert_response :created

    assert_no_difference("Doorkeeper::Application.count") do
      post "/oauth/register", params: { redirect_uris: [ "https://app.example.com/cb" ] }, as: :json
    end

    assert_response :too_many_requests
  end

  test "the authorization endpoint is limited" do
    30.times { get "/oauth/authorize", params: { client_id: "https://app.example.invalid/client.json" } }

    get "/oauth/authorize", params: { client_id: "https://app.example.invalid/client.json" }

    assert_response :too_many_requests
  end

  test "one token is limited on the MCP endpoint, without affecting another" do
    token = issue_token
    120.times { |i| mcp_request("tools/list", token:, headers: { "REMOTE_ADDR" => "203.0.113.#{i}" }) }
    assert_response :success

    mcp_request("tools/list", token:, headers: { "REMOTE_ADDR" => "203.0.113.200" })
    assert_response :too_many_requests

    mcp_request("tools/list", token: issue_token, headers: { "REMOTE_ADDR" => "203.0.113.201" })
    assert_response :success
  end

  test "the floor applies to anything from one address" do
    600.times { get "/oauth/login" }

    get "/oauth/login"

    assert_response :too_many_requests
  end

  test "an oversized OAuth request is refused before it is parsed" do
    post "/oauth/register", params: { client_name: "x" * 70.kilobytes }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :forbidden
  end

  test "the health check is never limited" do
    700.times { get "/up" }

    assert_response :success
  end

  test "a spoofed client IP header does not raise" do
    get "/oauth/login", headers: { "Client-Ip" => "1.2.3.4", "X-Forwarded-For" => "5.6.7.8" }

    assert_response :success
  end

  test "a malformed login body does not raise" do
    post "/oauth/login", params: "email_address[=x&%", headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    assert_not_equal 500, response.status
  end
end
