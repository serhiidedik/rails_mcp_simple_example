require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @post = posts(:one)
    @comment = comments(:one)
  end

  test "index lists only the comments of the post" do
    get post_comments_url(@post), as: :json

    assert_response :success
    assert_equal @post.comments.pluck(:id).sort, response.parsed_body.pluck("id").sort
  end

  test "index links to the next page" do
    get post_comments_url(@post, limit: 1), as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.size
    assert_match %r{/posts/#{@post.id}/comments\?cursor=.+>; rel="next"}, response.headers["Link"]
  end

  test "create adds a comment to the post in the URL, not one named in the body" do
    assert_difference("@post.comments.count") do
      post post_comments_url(@post), params: { comment: { body: "New", post_id: posts(:two).id, user_id: users(:alice).id } }, as: :json
    end

    assert_response :created
    assert_equal comment_url(Comment.last), response.location
    assert_equal @post.id, response.parsed_body["post_id"]
  end

  test "create reports validation errors" do
    post post_comments_url(@post), params: { comment: { body: " ", user_id: users(:alice).id } }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body["body"].present?
  end

  test "a missing post is a 404" do
    get post_comments_url(post_id: 0), as: :json
    assert_response :not_found

    post post_comments_url(post_id: 0), params: { comment: { body: "New", user_id: users(:alice).id } }, as: :json
    assert_response :not_found
  end

  test "a non-numeric id does not route" do
    get "/posts/abc/comments", as: :json
    assert_response :not_found

    get "/comments/abc", as: :json
    assert_response :not_found
  end

  test "create needs an owner, since REST has no sign-in" do
    post post_comments_url(@post), params: { comment: { body: "New" } }, as: :json

    assert_response :unprocessable_content
    assert_includes response.parsed_body.values.flatten, "User must exist"
  end

  test "REST has no sign-in, so it is not limited to the owner" do
    patch comment_url(comments(:two)), params: { comment: { body: "Edited" } }, as: :json

    assert_response :success
    assert_equal users(:bob), comments(:two).reload.user
  end

  test "show" do
    get comment_url(@comment), as: :json

    assert_response :success
    assert_equal @comment.body, response.parsed_body["body"]
  end

  test "update" do
    patch comment_url(@comment), params: { comment: { body: "Edited" } }, as: :json

    assert_response :success
    assert_equal "Edited", @comment.reload.body
  end

  test "destroy" do
    assert_difference("Comment.count", -1) { delete comment_url(@comment), as: :json }

    assert_response :no_content
  end

  test "a missing comment is a 404" do
    get comment_url(id: 0), as: :json
    assert_response :not_found
  end

  test "deleting a post through REST deletes its comments" do
    assert_difference("Comment.count", -2) { delete post_url(@post), as: :json }
  end
end
