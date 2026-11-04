require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "belongs to a post, and a post has many comments" do
    assert_equal posts(:one), comments(:one).post
    assert_includes posts(:one).comments, comments(:one)
    assert_not_includes posts(:one).comments, comments(:other)
  end

  test "needs a post and a body within the limit" do
    assert_not Comment.new(user: users(:alice), body: "text").valid?
    assert_not posts(:one).comments.new(user: users(:alice), body: " ").valid?
    assert_not posts(:one).comments.new(user: users(:alice), body: "x" * (Comment::BODY_MAX_LENGTH + 1)).valid?
    assert posts(:one).comments.new(user: users(:alice), body: "x" * Comment::BODY_MAX_LENGTH).valid?
  end

  test "needs an owner" do
    assert_not posts(:one).comments.new(body: "text").valid?
    assert_equal users(:bob), comments(:two).user
    assert_includes users(:bob).comments, comments(:two)
  end

  test "deleting a user deletes what they own, including comments on other people's posts" do
    assert_difference -> { Post.count } => -1, -> { Comment.count } => -2 do
      users(:bob).destroy!
    end
    assert Post.exists?(posts(:one).id)
    assert Comment.exists?(comments(:one).id)
  end

  test "the database refuses a record without an owner" do
    assert_raises(ActiveRecord::NotNullViolation) { Post.new(title: "x").save!(validate: false) }
    assert_raises(ActiveRecord::NotNullViolation) { posts(:one).comments.new(body: "x").save!(validate: false) }
  end

  test "deleting a post deletes its comments, and only its comments" do
    assert_difference("Comment.count", -2) { posts(:one).destroy! }

    assert Comment.exists?(comments(:other).id)
  end

  test "the database refuses a comment without a real post" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Comment.new(user: users(:alice), post_id: 0, body: "orphan").save!(validate: false)
    end
  end
end
