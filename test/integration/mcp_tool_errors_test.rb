require "test_helper"

# Other people work at the same time, so a model's view of the data goes stale between two calls.
# Each failure tells the model what happened and what to do next, instead of crashing the call.
class McpToolErrorsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = issue_token(user: users(:alice))
    @bob = issue_token(user: users(:bob))
  end

  test "commenting on a post its owner just deleted says so, and how to recover" do
    post_id = tool_result("list_posts", token: @alice)["posts"].find { |post| !post["mine"] }["id"]
    assert tool_result("delete_post", { id: post_id }, token: @bob)

    error = assert_no_difference("Comment.count") do
      tool_error("create_comment", { post_id:, body: "Too late" }, token: @alice)
    end

    assert_equal "not_found", error["code"]
    assert_equal "Post #{post_id} does not exist. It may have been deleted since you last read it.", error["message"]
    assert_includes error["next_step"], "Do not retry"
    assert_includes error["next_step"], "list_posts"

    # Following next_step works, and the post is gone from the list.
    assert_not_includes tool_result("list_posts", token: @alice)["posts"].pluck("id"), post_id
  end

  test "a comment deleted by its owner points at the comments" do
    assert tool_result("delete_comment", { id: comments(:two).id }, token: @bob)

    error = tool_error("get_comment", { id: comments(:two).id }, token: @alice)

    assert_equal "not_found", error["code"]
    assert_includes error["next_step"], "list_comments"
  end

  test "a comment on a post deleted while it was being saved is not_found, not a server error" do
    post_id = posts(:two).id
    race = lambda do |*|
      Post.find(post_id).destroy!
      raise ActiveRecord::InvalidForeignKey, "violates foreign key constraint"
    end

    stub_instance_method(Comment, :save, race) do
      error = tool_error("create_comment", { post_id:, body: "Too late" }, token: @alice)

      assert_equal "not_found", error["code"]
      assert_includes error["message"], "Post #{post_id}"
    end
  end

  test "a record deleted between the read and the write is not_found, not a false success" do
    {
      "update_post" => [ posts(:one), { title: "Too late" } ],
      "delete_post" => [ posts(:one), {} ],
      "update_comment" => [ comments(:one), { body: "Too late" } ],
      "delete_comment" => [ comments(:one), {} ]
    }.each do |name, (record, arguments)|
      race = lambda do |found|
        found.class.find(found.id).destroy!
        true
      end

      Comment.transaction(requires_new: true) do
        stub_instance_method(Actor, :may_change?, race) do
          error = tool_error(name, arguments.merge(id: record.id), token: @alice)

          assert_equal "not_found", error["code"], name
          assert_includes error["message"], "#{record.class.name} #{record.id}", name
        end

        raise ActiveRecord::Rollback
      end
    end
  end

  test "someone else's record is not_owner, and says not to retry" do
    error = tool_error("delete_post", { id: posts(:two).id }, token: @alice)

    assert_equal "not_owner", error["code"]
    assert_equal "Post #{posts(:two).id} belongs to another user. You can only change your own posts.", error["message"]
    assert_includes error["next_step"], "Do not retry"
    assert Post.exists?(posts(:two).id)
  end

  test "a failed validation names the fields to correct" do
    error = tool_error("create_comment", { post_id: posts(:one).id, body: "   " }, token: @alice)

    assert_equal "validation_failed", error["code"]
    assert_equal [ "can't be blank" ], error.dig("fields", "body")
    assert_includes error["next_step"], "call the tool again"
  end

  test "the server tells clients how to handle errors and ownership" do
    instructions = mcp_request("initialize", { protocolVersion: McpTestHelpers::LEGACY_PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "test", version: "1" } }, token: @alice).dig("result", "instructions")

    assert_includes instructions, "next_step"
    assert_includes instructions, "Only the owner"
  end
end
