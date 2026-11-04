# Speaks MCP the way a client does, over real HTTP requests.
module McpTestHelpers
  LEGACY_PROTOCOL_VERSION = "2025-11-25".freeze
  MODERN_PROTOCOL_VERSION = "2026-07-28".freeze

  def issue_token(scopes: Doorkeeper.configuration.scopes.to_s, resource: Oauth::ResourceIndicator.canonical, user: users(:alice), **attributes)
    Doorkeeper::AccessToken.create!(
      application: create_public_client,
      resource_owner_id: user.id,
      scopes:,
      resource:,
      expires_in: 1.hour.to_i,
      **attributes
    ).plaintext_token
  end

  def mcp_headers(token:, **overrides)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "Authorization" => token && "Bearer #{token}",
      "MCP-Protocol-Version" => LEGACY_PROTOCOL_VERSION
    }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def mcp_request(method, params = {}, token:, headers: {}, id: 1)
    body = { jsonrpc: "2.0", id:, method:, params: }.compact
    post "/mcp", params: body.to_json, headers: mcp_headers(token:).merge(headers)
    response.parsed_body
  end

  def call_tool(name, arguments = {}, token:)
    mcp_request("tools/call", { name:, arguments: }, token:)
  end

  # The structured result of a successful tool call.
  def tool_result(name, arguments = {}, token:)
    result = call_tool(name, arguments, token:)
    assert_response :success
    assert_not result.dig("result", "isError"), result.inspect
    result.dig("result", "structuredContent")
  end

  # The error of a failed tool call: code, message, next_step, and sometimes fields.
  def tool_error(name, arguments = {}, token:)
    result = call_tool(name, arguments, token:)
    assert_response :success
    assert result.dig("result", "isError"), result.inspect
    JSON.parse(result.dig("result", "content", 0, "text")).fetch("error")
  end

  def www_authenticate
    response.headers["WWW-Authenticate"]
  end
end
