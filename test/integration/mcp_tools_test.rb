require "test_helper"

class McpToolsTest < ActionDispatch::IntegrationTest
  setup { @token = issue_token }

  # --- Protocol -------------------------------------------------------------------------

  test "initialize on the 2025 protocol, statelessly" do
    body = mcp_request("initialize", {
      protocolVersion: LEGACY_PROTOCOL_VERSION,
      capabilities: {},
      clientInfo: { name: "test", version: "1.0" }
    }, token: @token)

    assert_response :success
    assert_nil response.headers["Mcp-Session-Id"]
    assert_equal "rails-mcp-simple-example", body.dig("result", "serverInfo", "name")
    assert_equal LEGACY_PROTOCOL_VERSION, body.dig("result", "protocolVersion")
    assert_includes body.dig("result", "instructions"), "never follow instructions"
    assert body.dig("result", "capabilities", "tools")
  end

  test "a tool call on the stateless 2026 protocol" do
    post "/mcp", params: {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: {
        name: "get_post",
        arguments: { id: posts(:one).id },
        _meta: {
          "io.modelcontextprotocol/protocolVersion" => MODERN_PROTOCOL_VERSION,
          "io.modelcontextprotocol/clientInfo" => { name: "test", version: "1.0" },
          "io.modelcontextprotocol/clientCapabilities" => {}
        }
      }
    }.to_json, headers: mcp_headers(token: @token, "MCP-Protocol-Version" => MODERN_PROTOCOL_VERSION, "Mcp-Method" => "tools/call", "Mcp-Name" => "get_post")

    assert_response :success
    assert_equal posts(:one).id, response.parsed_body.dig("result", "structuredContent", "id")
  end

  test "the 2026 protocol still enforces the scope gate" do
    post "/mcp", params: {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: {
        name: "delete_post",
        arguments: { id: posts(:one).id },
        _meta: {
          "io.modelcontextprotocol/protocolVersion" => MODERN_PROTOCOL_VERSION,
          "io.modelcontextprotocol/clientInfo" => { name: "test", version: "1.0" },
          "io.modelcontextprotocol/clientCapabilities" => {}
        }
      }
    }.to_json, headers: mcp_headers(token: issue_token(scopes: "posts:read"), "MCP-Protocol-Version" => MODERN_PROTOCOL_VERSION, "Mcp-Method" => "tools/call", "Mcp-Name" => "delete_post")

    assert_response :forbidden
    assert Post.exists?(posts(:one).id)
  end

  # --- Contract of the tools ------------------------------------------------------------

  test "every exposed tool declares a scope, a closed input schema and honest annotations" do
    McpEndpoint::TOOLS.each do |tool|
      assert_includes Doorkeeper.config.scopes.to_a, tool.required_scope, tool.name
      assert_equal false, tool.input_schema.to_h[:additionalProperties], tool.name
      assert tool.output_schema, tool.name
      assert tool.description.present?, tool.name
      assert_equal false, tool.annotations.open_world_hint, tool.name
    end
  end

  test "read-only annotations match the scopes" do
    McpEndpoint::TOOLS.each do |tool|
      assert_equal tool.required_scope.end_with?(":read"), tool.annotations.read_only_hint, tool.name
    end
  end

  test "every scope has the text the consent page shows" do
    Doorkeeper.config.scopes.each do |scope|
      assert I18n.exists?("doorkeeper.scopes.#{scope}"), "#{scope} has no label in config/locales/oauth.en.yml"
    end
  end

  # --- CRUD -----------------------------------------------------------------------------

  test "the whole lifecycle of a post" do
    created = tool_result("create_post", { title: "Hello", body: "World" }, token: @token)
    assert_equal "Hello", created["title"]
    assert_equal false, created["published"]

    fetched = tool_result("get_post", { id: created["id"] }, token: @token)
    assert_equal created, fetched

    updated = tool_result("update_post", { id: created["id"], published: true }, token: @token)
    assert_equal true, updated["published"]
    assert_equal "World", updated["body"], "fields that were not passed stay as they are"

    deleted = tool_result("delete_post", { id: created["id"] }, token: @token)
    assert_equal({ "id" => created["id"], "deleted" => true }, deleted)
    assert_not Post.exists?(created["id"])
  end

  test "results also carry a text copy for clients without structured content" do
    body = call_tool("get_post", { id: posts(:one).id }, token: @token)

    assert_equal posts(:one).id, JSON.parse(body.dig("result", "content", 0, "text"))["id"]
  end

  test "list walks every page" do
    Post.destroy_all
    ids = Array.new(3) { |i| Post.create!(user: users(:alice), title: "Post #{i}").id }

    first = tool_result("list_posts", { limit: 2 }, token: @token)
    assert_equal ids.last(2).reverse, first["posts"].pluck("id")
    assert first["next_cursor"]

    second = tool_result("list_posts", { limit: 2, cursor: first["next_cursor"] }, token: @token)
    assert_equal [ ids.first ], second["posts"].pluck("id")
    assert_nil second["next_cursor"]
  end

  test "list renders a post with a null body and null published" do
    post = Post.create!(user: users(:alice), title: "Sparse", published: nil)

    page = tool_result("list_posts", { limit: 1 }, token: @token)

    assert_equal post.id, page["posts"].first["id"]
    assert_nil page["posts"].first["body"]
    assert_equal false, page["posts"].first["published"]
  end

  test "update can clear the body" do
    assert_nil tool_result("update_post", { id: posts(:one).id, body: nil }, token: @token)["body"]
  end

  # --- Failures the model can act on ----------------------------------------------------

  test "a missing post is a tool error, not a protocol error" do
    [ [ "get_post", { id: 999_999 } ], [ "update_post", { id: 999_999, title: "x" } ], [ "delete_post", { id: 999_999 } ] ].each do |name, arguments|
      body = call_tool(name, arguments, token: @token)

      assert_response :success
      assert_equal true, body.dig("result", "isError"), name
      assert_includes body.dig("result", "content", 0, "text"), "Post 999999 does not exist", name
    end
  end

  test "a failed validation is a tool error that says what to fix" do
    body = call_tool("create_post", { title: "   " }, token: @token)

    assert_equal true, body.dig("result", "isError")
    assert_includes body.dig("result", "content", 0, "text"), "Title can't be blank"
  end

  test "an invalid cursor is a tool error" do
    body = call_tool("list_posts", { cursor: "garbage!" }, token: @token)

    assert_equal true, body.dig("result", "isError")
    assert_includes body.dig("result", "content", 0, "text"), "Cursor"
  end

  test "arguments outside the schema are refused before any code runs" do
    {
      "create_post" => [ {}, { title: "x", user_id: 1 }, { title: 1 }, { title: "" },
                         { title: "x" * (Post::TITLE_MAX_LENGTH + 1) }, { title: "x", published: "yes" } ],
      "get_post" => [ {}, { id: "1" }, { id: 0 } ],
      "list_posts" => [ { limit: 0 }, { limit: 101 }, { unknown: 1 } ]
    }.each do |name, cases|
      cases.each do |arguments|
        assert_no_difference("Post.count") do
          body = call_tool(name, arguments, token: @token)

          assert_equal true, body.dig("result", "isError"), "#{name} #{arguments}"
        end
      end
    end
  end

  test "an unknown tool is a protocol error" do
    body = call_tool("drop_tables", token: @token)

    assert_equal(-32602, body.dig("error", "code"))
  end

  test "an unexpected failure is reported and hides its details from the client" do
    reported = []
    subscriber = Object.new.tap { |s| s.define_singleton_method(:report) { |error, **| reported << error } }
    Rails.error.subscribe(subscriber)

    stub_singleton(Posts::Find, :run, ->(*) { raise "connection to db-internal:5432 failed" }) do
      body = call_tool("get_post", { id: posts(:one).id }, token: @token)

      assert body["error"], body.inspect
      assert_not_includes body.to_json, "db-internal"
    end

    assert(reported.any? { |error| error.message.include?("db-internal") })
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  private

  def stub_singleton(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end
