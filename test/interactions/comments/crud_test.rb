require "test_helper"

class Comments::CrudTest < ActiveSupport::TestCase
  test "create adds a comment to the post" do
    comment = Comments::Create.run!(post_id: posts(:two).id, body: "  Kept as written  ")

    assert_equal posts(:two), comment.post
    assert_equal "  Kept as written  ", comment.body
  end

  test "create reports a failed validation through errors" do
    outcome = Comments::Create.run(post_id: posts(:two).id, body: " ")

    assert_not outcome.valid?
    assert_includes outcome.errors.full_messages, "Body can't be blank"
  end

  test "create on a missing post raises not found" do
    assert_raises(ActiveRecord::RecordNotFound) { Comments::Create.run(post_id: 0, body: "text") }
  end

  test "create cannot be pointed at other columns" do
    comment = Comments::Create.run!(post_id: posts(:two).id, body: "text", id: 999_999, created_at: 1.year.ago)

    assert_not_equal 999_999, comment.id
    assert_in_delta Time.current, comment.created_at, 1.minute
  end

  test "find, and not found" do
    assert_equal comments(:one), Comments::Find.run!(id: comments(:one).id)
    assert_raises(ActiveRecord::RecordNotFound) { Comments::Find.run(id: 0) }
  end

  test "update changes the body and never the post" do
    comment = Comments::Update.run!(id: comments(:one).id, body: "Edited", post_id: posts(:two).id)

    assert_equal "Edited", comment.reload.body
    assert_equal posts(:one), comment.post
  end

  test "update needs a body" do
    assert_not Comments::Update.run(id: comments(:one).id).valid?
    assert_not Comments::Update.run(id: comments(:one).id, body: " ").valid?
    assert_equal "First comment", comments(:one).reload.body
  end

  test "destroy removes the comment" do
    assert_difference("Comment.count", -1) { Comments::Destroy.run!(id: comments(:one).id) }
    assert_raises(ActiveRecord::RecordNotFound) { Comments::Destroy.run(id: comments(:one).id) }
  end

  test "list holds only the comments of that post, newest first, and pages through them" do
    post = posts(:two)
    Comment.where(post:).delete_all
    created = Array.new(3) { |i| post.comments.create!(body: "Comment #{i}") }

    first = Comments::List.run!(post_id: post.id, limit: 2)
    assert_equal created.last(2).reverse, first.records

    last = Comments::List.run!(post_id: post.id, limit: 2, cursor: first.next_cursor)
    assert_equal [ created.first ], last.records
    assert_nil last.next_cursor
  end

  test "list on a missing post raises not found, rather than an empty page" do
    assert_raises(ActiveRecord::RecordNotFound) { Comments::List.run(post_id: 0) }
  end

  test "list refuses a bad limit and a bad cursor" do
    assert_not Comments::List.run(post_id: posts(:one).id, limit: 0).valid?
    assert_not Comments::List.run(post_id: posts(:one).id, cursor: "!!!").valid?
  end
end
