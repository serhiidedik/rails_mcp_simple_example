require "test_helper"
require "rake"

# The reference is only worth reading if it is true. These tests keep it that way.
class McpApiReferenceTest < ActionDispatch::IntegrationTest
  test "the committed contract matches the tool classes" do
    assert_equal McpApiReference.new.tools_json, McpApiReference::TOOLS_FILE.read, "docs/mcp-tools.json is stale: run bin/rails mcp:docs"
  end

  test "the committed contract is exactly what a client gets from tools/list" do
    committed = JSON.parse(McpApiReference::TOOLS_FILE.read).fetch("tools")

    assert_equal committed, mcp_request("tools/list", token: issue_token).dig("result", "tools")
  end

  test "GET /docs/tools.json serves the contract, with no token" do
    get "/docs/tools.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal JSON.parse(McpApiReference::TOOLS_FILE.read), response.parsed_body
  end

  test "the root page documents every tool and scope" do
    get "/"

    assert_response :success
    assert_equal "text/html", response.media_type

    McpEndpoint::TOOLS.each do |tool|
      assert_select "section##{tool.tool_name} h3 code", tool.tool_name
      assert_select "section##{tool.tool_name} .scope", tool.required_scope
    end
    Doorkeeper.configuration.scopes.each { |scope| assert_select "#scopes code", scope }
  end

  test "the root page shows the constraints from the schemas, and nested result fields" do
    get "/"

    assert_select "section#list_posts td", /From 1 to #{Posts::List::MAX_LIMIT}\. Default: #{Posts::List::DEFAULT_LIMIT}\./
    assert_select "section#create_post td", /From 1 to #{Post::TITLE_MAX_LENGTH} characters\./
    assert_select "section#list_posts td code", "posts[].id"
  end

  test "the root page describes what each tool does to data" do
    get "/"

    assert_select "section#get_post .tool-meta", /Read-only, safe to retry/
    assert_select "section#list_posts .tool-meta", /Read-only, safe to retry/
    assert_select "section#create_post .tool-meta", /Adds data/
    assert_select "section#update_post .tool-meta", /Destructive, safe to retry/
    assert_select "section#delete_post .tool-meta", /Destructive, safe to retry/
  end

  test "read tools tell clients plainly that they destroy nothing" do
    [ Posts::ListTool, Posts::GetTool ].each do |tool|
      annotations = tool.to_h.fetch(:annotations)

      assert annotations.fetch(:readOnlyHint)
      assert_not annotations.fetch(:destructiveHint)
    end
  end

  test "the root page runs no script and loads nothing from anywhere" do
    get "/"

    assert_empty css_select("script, link[rel=stylesheet], img, iframe, form")
    policy = response.headers["Content-Security-Policy"]
    assert_includes policy, "default-src 'none'"
    assert_includes policy, "form-action 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    assert_not_includes policy, "script-src"
  end

  test "the root page reads nothing from the database" do
    assert_no_queries { get "/" }
    assert_response :success
  end

  test "the root page mentions the local sign-in only in development" do
    get "/"
    assert_not_includes response.body, "SEED_USER_EMAIL"
  end

  McpEndpoint::TOOLS.each do |tool|
    test "the documented example of #{tool.tool_name} works against the real endpoint" do
      arguments = tool.example.fetch(:arguments)
      arguments = arguments.merge(id: posts(:one).id) if arguments.key?(:id)

      actual = tool_result(tool.tool_name, arguments, token: issue_token)
      documented = tool.example.fetch(:result).deep_stringify_keys

      assert_nothing_raised { tool.output_schema.validate_result(documented) }
      assert_equal documented.keys.sort, actual.keys.sort
    end
  end

  test "the documented list cursor is one the server accepts" do
    cursor = Posts::ListTool.example.fetch(:result).fetch(:next_cursor)

    assert tool_result("list_posts", { cursor: }, token: issue_token).key?("posts")
  end

  test "mcp:dev_token refuses to run outside development" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("mcp:dev_token")

    assert_no_difference -> { Doorkeeper::AccessToken.count } do
      assert_raises(SystemExit) { capture_io { Rake::Task["mcp:dev_token"].execute } }
    end
  end
end
