require "test_helper"

# The journey of a real client, from nothing to a post being deleted.
class McpOauthFlowTest < ActionDispatch::IntegrationTest
  test "discovery, registration, one consent for every tool, refresh, revocation" do
    # No token: the 401 points at the metadata.
    mcp_request("tools/list", token: nil)
    assert_response :unauthorized
    metadata_path = URI.parse(www_authenticate[/resource_metadata="([^"]+)"/, 1]).path
    challenged_scope = www_authenticate[/scope="([^"]+)"/, 1]

    # The metadata names the resource and the authorization server.
    get metadata_path
    resource = response.parsed_body["resource"]
    issuer = response.parsed_body["authorization_servers"].first

    get "#{URI.parse(issuer).path}/.well-known/oauth-authorization-server"
    assert_equal issuer, response.parsed_body["issuer"]
    assert_includes response.parsed_body["code_challenge_methods_supported"], "S256"
    registration_endpoint = URI.parse(response.parsed_body["registration_endpoint"]).path

    # Registration.
    post registration_endpoint, params: { client_name: "Journey client", redirect_uris: [ LOOPBACK_REDIRECT_URI ] }, as: :json
    assert_response :created
    client = Doorkeeper::Application.by_uid(response.parsed_body["client_id"])

    # One consent, for everything the server offers.
    tokens = obtain_tokens(client, scope: challenged_scope, resource:)
    assert_equal Doorkeeper.configuration.scopes.to_a.sort, tokens["scope"].split.sort

    # Every operation of every entity works with that one token.
    token = tokens["access_token"]
    assert tool_result("list_posts", token:)
    created = tool_result("create_post", { title: "Hello" }, token:)
    comment = tool_result("create_comment", { post_id: created["id"], body: "Hi" }, token:)
    assert tool_result("list_comments", { post_id: created["id"] }, token:)
    assert tool_result("delete_comment", { id: comment["id"] }, token:)
    assert tool_result("delete_post", { id: tool_result("create_post", { title: "Short lived" }, token:)["id"] }, token:)

    # A refreshed token keeps working.
    refresh(client, tokens["refresh_token"], resource:)
    assert_response :success
    refreshed = response.parsed_body
    assert tool_result("get_post", { id: created["id"] }, token: refreshed["access_token"])

    # Revocation takes effect immediately, on the very next request.
    post "/oauth/revoke", params: { token: refreshed["access_token"], client_id: client.uid }
    mcp_request("tools/list", token: refreshed["access_token"])
    assert_response :unauthorized
  end

  test "a client can still ask for less, and is held to it" do
    client = create_public_client
    tokens = obtain_tokens(client, scope: "posts:read")
    assert_equal "posts:read", tokens["scope"]

    call_tool("create_post", { title: "Hello" }, token: tokens["access_token"])
    assert_response :forbidden
    assert_includes www_authenticate, %(scope="posts:write")
  end

  private

  LOOPBACK_REDIRECT_URI = OauthTestHelpers::LOOPBACK_REDIRECT_URI
end
