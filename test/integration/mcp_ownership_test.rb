require "test_helper"

# Everyone signed in can read everything, and only the owner can change it. The owner always comes
# from the token: alice holds the token here, and posts(:two) and comments(:two) belong to bob.
class McpOwnershipTest < ActionDispatch::IntegrationTest
  setup { @token = issue_token(user: users(:alice)) }

  test "what a user creates belongs to the user in the token" do
    post = tool_result("create_post", { title: "Mine" }, token: @token)
    assert_equal users(:alice).id, post["user_id"]
    assert_equal true, post["mine"]

    comment = tool_result("create_comment", { post_id: posts(:two).id, body: "On a post of bob" }, token: @token)
    assert_equal users(:alice).id, comment["user_id"]
    assert_equal true, comment["mine"]
  end

  test "a client cannot claim to be someone else" do
    [
      [ "create_post", { title: "Forged", user_id: users(:bob).id } ],
      [ "create_comment", { post_id: posts(:one).id, body: "Forged", user_id: users(:bob).id } ],
      [ "update_post", { id: posts(:two).id, title: "Forged", actor: { user_id: users(:bob).id } } ],
      [ "delete_post", { id: posts(:two).id, actor: { user_id: nil } } ],
      [ "get_post", { id: posts(:one).id, actor: nil } ]
    ].each do |name, arguments|
      assert_no_difference [ "Post.count", "Comment.count" ] do
        assert call_tool(name, arguments, token: @token).dig("result", "isError"), name
      end
    end
    assert_equal "MyString", posts(:two).reload.title
  end

  test "anyone can read a record of someone else, and sees that it is not theirs" do
    post = tool_result("get_post", { id: posts(:two).id }, token: @token)
    assert_equal users(:bob).id, post["user_id"]
    assert_equal false, post["mine"]

    comment = tool_result("get_comment", { id: comments(:two).id }, token: @token)
    assert_equal users(:bob).id, comment["user_id"]
    assert_equal false, comment["mine"]
  end

  test "list marks what is mine, and can show only that" do
    everything = tool_result("list_posts", token: @token)["posts"]
    assert_equal [ true, false ], everything.pluck("mine").uniq.sort_by { |mine| mine ? 0 : 1 }

    mine = tool_result("list_posts", { mine: true }, token: @token)["posts"]
    assert_equal [ posts(:one).id ], mine.pluck("id")

    comments = tool_result("list_comments", { post_id: posts(:one).id }, token: @token)["comments"]
    assert_equal [ true, false ], comments.pluck("mine").sort_by { |value| value ? 0 : 1 }
  end

  test "changing a record of someone else is a readable refusal, and changes nothing" do
    {
      "update_post" => { id: posts(:two).id, title: "Taken over" },
      "delete_post" => { id: posts(:two).id },
      "update_comment" => { id: comments(:two).id, body: "Taken over" },
      "delete_comment" => { id: comments(:two).id }
    }.each do |name, arguments|
      assert_no_difference [ "Post.count", "Comment.count" ] do
        result = call_tool(name, arguments, token: @token).fetch("result")

        assert_response :success
        assert result["isError"], name
        assert_match(/only change your own/, result.dig("content", 0, "text"), name)
      end
    end
    assert_equal "MyString", posts(:two).reload.title
    assert_equal "Second comment", comments(:two).reload.body
  end

  test "the owner can change their own, and so can the other user with their own" do
    assert tool_result("update_post", { id: posts(:one).id, title: "Edited" }, token: @token)
    assert_equal "Edited", posts(:one).reload.title

    bob = issue_token(user: users(:bob))
    assert tool_result("update_post", { id: posts(:two).id, title: "By bob" }, token: bob)
    assert call_tool("update_post", { id: posts(:one).id, title: "By bob" }, token: bob).dig("result", "isError")
    assert_equal "Edited", posts(:one).reload.title
  end

  test "the owner of a post can delete it, with the comments of others on it" do
    assert_difference("Comment.count", -2) { tool_result("delete_post", { id: posts(:one).id }, token: @token) }
  end

  test "every tool that changes something requires an actor, so no adapter can forget it" do
    [ Posts::Update, Posts::Destroy, Comments::Update, Comments::Destroy ].each do |operation|
      assert_not operation.run(id: 1).valid?, operation.name
      assert_not operation.run(id: 1).errors[:actor].empty?, operation.name
    end
  end
end
