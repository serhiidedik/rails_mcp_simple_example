require "test_helper"

class McpCommentToolsTest < ActionDispatch::IntegrationTest
  setup { @token = issue_token }

  test "the whole lifecycle of a comment" do
    created = tool_result("create_comment", { post_id: posts(:two).id, body: "Hello" }, token: @token)
    assert_equal posts(:two).id, created["post_id"]

    assert_equal created, tool_result("get_comment", { id: created["id"] }, token: @token)

    listed = tool_result("list_comments", { post_id: posts(:two).id }, token: @token)
    assert_includes listed["comments"].pluck("id"), created["id"]
    assert_not_includes listed["comments"].pluck("id"), comments(:one).id

    updated = tool_result("update_comment", { id: created["id"], body: "Edited" }, token: @token)
    assert_equal "Edited", updated["body"]

    deleted = tool_result("delete_comment", { id: created["id"] }, token: @token)
    assert_equal({ "id" => created["id"], "deleted" => true }, deleted)
    assert_not Comment.exists?(created["id"])
  end

  test "list walks every page" do
    post = posts(:one)
    2.times { |i| post.comments.create!(user: users(:alice), body: "More #{i}") }
    seen = []
    cursor = nil

    loop do
      page = tool_result("list_comments", { post_id: post.id, limit: 2, cursor: }.compact, token: @token)
      seen.concat(page["comments"].pluck("id"))
      cursor = page["next_cursor"] or break
    end

    assert_equal post.comments.pluck(:id).sort.reverse, seen
  end

  test "a missing post or comment is a tool error that names it" do
    [
      [ "list_comments", { post_id: 999_999 }, "Post 999999 does not exist" ],
      [ "create_comment", { post_id: 999_999, body: "x" }, "Post 999999 does not exist" ],
      [ "get_comment", { id: 999_999 }, "Comment 999999 does not exist" ],
      [ "update_comment", { id: 999_999, body: "x" }, "Comment 999999 does not exist" ],
      [ "delete_comment", { id: 999_999 }, "Comment 999999 does not exist" ]
    ].each do |name, arguments, message|
      assert_includes tool_error(name, arguments, token: @token)["message"], message, name
    end
  end

  test "a failed validation is a tool error that says what to fix" do
    result = call_tool("update_comment", { id: comments(:one).id, body: "   " }, token: @token).fetch("result")

    assert result["isError"]
    assert_includes result.dig("content", 0, "text"), "can't be blank"
  end

  test "a comment cannot be moved to another post" do
    result = call_tool("update_comment", { id: comments(:one).id, body: "x", post_id: posts(:two).id }, token: @token).fetch("result")

    assert result["isError"]
    assert_equal posts(:one), comments(:one).reload.post
  end

  test "each operation needs its own scope, and post scopes do not reach comments" do
    {
      "list_comments" => [ { post_id: posts(:one).id }, "comments:read" ],
      "get_comment" => [ { id: comments(:one).id }, "comments:read" ],
      "create_comment" => [ { post_id: posts(:one).id, body: "x" }, "comments:write" ],
      "update_comment" => [ { id: comments(:one).id, body: "x" }, "comments:write" ],
      "delete_comment" => [ { id: comments(:one).id }, "comments:delete" ]
    }.each do |name, (arguments, scope)|
      token = issue_token(scopes: (Doorkeeper.configuration.scopes.to_a - [ scope ]).join(" "))

      assert_no_difference("Comment.count") { call_tool(name, arguments, token:) }

      assert_response :forbidden, name
      assert_includes www_authenticate, %(scope="#{scope}"), name
    end
  end

  test "deleting a post through MCP deletes its comments" do
    assert_difference("Comment.count", -2) do
      tool_result("delete_post", { id: posts(:one).id }, token: @token)
    end
  end
end
