require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "belongs to a post, and a post has many comments" do
    assert_equal posts(:one), comments(:one).post
    assert_includes posts(:one).comments, comments(:one)
    assert_not_includes posts(:one).comments, comments(:other)
  end

  test "needs a post and a body within the limit" do
    assert_not Comment.new(body: "text").valid?
    assert_not posts(:one).comments.new(body: " ").valid?
    assert_not posts(:one).comments.new(body: "x" * (Comment::BODY_MAX_LENGTH + 1)).valid?
    assert posts(:one).comments.new(body: "x" * Comment::BODY_MAX_LENGTH).valid?
  end

  test "deleting a post deletes its comments, and only its comments" do
    assert_difference("Comment.count", -2) { posts(:one).destroy! }

    assert Comment.exists?(comments(:other).id)
  end

  test "the database refuses a comment without a real post" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Comment.new(post_id: 0, body: "orphan").save!(validate: false)
    end
  end
end
