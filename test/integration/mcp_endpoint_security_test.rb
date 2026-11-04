require "test_helper"

class McpEndpointSecurityTest < ActionDispatch::IntegrationTest
  METADATA_URL = "http://localhost:3000/.well-known/oauth-protected-resource/mcp".freeze

  # --- Discovery ------------------------------------------------------------------------

  test "publishes the protected resource metadata without authentication" do
    get "/.well-known/oauth-protected-resource/mcp"

    assert_response :success
    metadata = response.parsed_body
    assert_equal "http://localhost:3000/mcp", metadata["resource"]
    assert_equal [ "http://localhost:3000" ], metadata["authorization_servers"]
    assert_equal Doorkeeper.configuration.scopes.to_a, metadata["scopes_supported"]
    assert_equal [ "header" ], metadata["bearer_methods_supported"]
  end

  test "a request without a token gets a 401 that starts discovery" do
    mcp_request("tools/list", token: nil)

    assert_response :unauthorized
    assert_includes www_authenticate, %(resource_metadata="#{METADATA_URL}")
    assert_includes www_authenticate, %(scope="#{Doorkeeper.configuration.scopes}")
    assert_not_includes www_authenticate, "error="
  end

  # --- Token validation -----------------------------------------------------------------

  test "accepts a valid token" do
    mcp_request("tools/list", token: issue_token)

    assert_response :success
  end

  test "rejects every kind of invalid token with the same 401" do
    {
      "unknown" => "not-a-real-token",
      "revoked" => issue_token(revoked_at: 1.minute.ago),
      "expired" => issue_token(created_at: 2.hours.ago),
      "issued for another resource" => issue_token(resource: "https://other.example/mcp"),
      "without an audience" => issue_token(resource: nil),
      "oversized" => "x" * 9000
    }.each do |kind, token|
      mcp_request("tools/list", token:)

      assert_response :unauthorized, kind
      assert_includes www_authenticate, %(error="invalid_token"), kind
      assert_includes www_authenticate, METADATA_URL, kind
    end
  end

  test "a token issued to the user for another resource reads nothing" do
    token = issue_token(resource: "https://other.example/mcp")

    body = call_tool("list_posts", token:)

    assert_response :unauthorized
    assert_not body.key?("result")
  end

  test "a token in the query string does not authenticate" do
    post "/mcp?access_token=#{issue_token}", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: mcp_headers(token: nil)

    assert_response :unauthorized
  end

  test "the session cookie of the OAuth pages does not authenticate" do
    sign_in
    mcp_request("tools/list", token: nil)

    assert_response :unauthorized
  end

  # --- Scopes and step-up ---------------------------------------------------------------

  test "a missing scope is an HTTP 403 naming the scope, which starts step-up" do
    { "create_post" => "posts:write", "update_post" => "posts:write", "delete_post" => "posts:delete" }.each do |tool, scope|
      assert_no_difference("Post.count") do
        call_tool(tool, { id: posts(:one).id, title: "x" }, token: issue_token(scopes: "posts:read"))
      end

      assert_response :forbidden, tool
      assert_includes www_authenticate, %(error="insufficient_scope"), tool
      assert_includes www_authenticate, %(scope="#{scope}"), tool
      assert_includes www_authenticate, %(resource_metadata="#{METADATA_URL}"), tool
    end
  end

  test "write does not imply delete, or read" do
    token = issue_token(scopes: "posts:write")

    call_tool("delete_post", { id: posts(:one).id }, token:)
    assert_response :forbidden
    assert Post.exists?(posts(:one).id)

    call_tool("get_post", { id: posts(:one).id }, token:)
    assert_response :forbidden
  end

  test "any valid token can discover the tools, so a client knows what to ask for" do
    body = mcp_request("tools/list", token: issue_token(scopes: "posts:read"))

    assert_response :success
    assert_equal McpEndpoint::TOOLS.map(&:tool_name).sort, body.dig("result", "tools").pluck("name").sort
  end

  test "the scope check holds when the HTTP gate is bypassed" do
    original = McpEndpoint.instance_method(:required_scopes)
    McpEndpoint.define_method(:required_scopes) { [] }

    assert_no_difference("Post.count") do
      body = call_tool("create_post", { title: "x" }, token: issue_token(scopes: "posts:read"))

      assert_equal(-32600, body.dig("error", "code"))
      assert_includes body["error"].to_json, "posts:write"
    end
  ensure
    McpEndpoint.define_method(:required_scopes, original)
    McpEndpoint.send(:private, :required_scopes)
  end

  # --- Transport ------------------------------------------------------------------------

  test "refuses a foreign Origin (DNS rebinding)" do
    mcp_request("tools/list", token: issue_token, headers: { "Origin" => "https://evil.example" })

    assert_response :forbidden
  end

  test "accepts a same-origin Origin and an allowlisted one" do
    mcp_request("tools/list", token: issue_token, headers: { "Origin" => "http://localhost:3000" })
    assert_response :success

    with_allowed_origins("https://inspector.example") do
      mcp_request("tools/list", token: issue_token, headers: { "Origin" => "https://inspector.example" })
      assert_response :success
    end
  end

  test "refuses a foreign Host" do
    host! "evil.example"
    mcp_request("tools/list", token: issue_token)

    assert_response :forbidden
  end

  test "the Origin and Host checks run before the token is looked at" do
    mcp_request("tools/list", token: nil, headers: { "Origin" => "https://evil.example" })

    assert_response :forbidden
    assert_nil www_authenticate
  end

  test "refuses a body over the limit" do
    token = issue_token
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: { x: "x" * McpEndpoint::MAX_REQUEST_BYTES } }.to_json, headers: mcp_headers(token:)

    assert_response 413
  end

  test "malformed JSON is a JSON-RPC error, not a Rails error page" do
    post "/mcp", params: "{not json", headers: mcp_headers(token: issue_token)

    assert_response :bad_request
    assert_equal(-32700, response.parsed_body.dig("error", "code"))
  end

  test "a batch is refused" do
    post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "tools/list" } ].to_json, headers: mcp_headers(token: issue_token)

    assert_response :bad_request
    assert_equal(-32600, response.parsed_body.dig("error", "code"))
  end

  test "deeply nested JSON is refused without a crash" do
    deep = "[" * 200 + "]" * 200
    post "/mcp", params: %({"jsonrpc":"2.0","id":1,"method":"tools/list","params":#{deep}}), headers: mcp_headers(token: issue_token)

    assert_response :bad_request
  end

  test "GET is refused: there is no stream to open" do
    get "/mcp", headers: mcp_headers(token: issue_token)

    assert_response :method_not_allowed
  end

  test "DELETE needs a token and is a no-op: there is no session to end" do
    delete "/mcp", headers: mcp_headers(token: nil)
    assert_response :unauthorized

    assert_no_difference("Post.count") do
      delete "/mcp", headers: mcp_headers(token: issue_token)
    end
    assert_response :success
  end

  test "a notification gets an empty 202" do
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: mcp_headers(token: issue_token)

    assert_response :accepted
    assert_empty response.body
  end

  test "responses are not cacheable" do
    mcp_request("tools/list", token: issue_token)

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "tool arguments never reach the logs" do
    secret = "very-secret-post-content"
    token = issue_token
    output = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    ActiveRecord::Base.logger = nil

    tool_result("create_post", { title: secret }, token:)

    assert_includes output.string, "mcp.tool_call tool=create_post result=ok"
    assert_not_includes output.string, secret
    assert_not_includes output.string, token
  ensure
    Rails.logger = original
  end

  private

  def with_allowed_origins(*origins)
    settings = Rails.configuration.x.mcp
    original = settings.allowed_origins
    settings.allowed_origins = origins
    yield
  ensure
    settings.allowed_origins = original
  end
end
