require "test_helper"

class Posts::CrudTest < ActiveSupport::TestCase
  setup { @post = posts(:one) }

  test "create persists a valid post and defaults published to false" do
    outcome = Posts::Create.run(user_id: users(:alice).id, title: "Hello", body: "  keeps whitespace ")

    assert outcome.valid?
    assert_predicate outcome.result, :persisted?
    assert_equal "  keeps whitespace ", outcome.result.body
    assert_equal false, outcome.result.published
  end

  test "create reports the model validation errors" do
    outcome = Posts::Create.run(user_id: users(:alice).id, title: " ")

    assert_not outcome.valid?
    assert outcome.errors.of_kind?(:title, :blank)
  end

  test "create drops inputs it does not declare" do
    outcome = Posts::Create.run(user_id: users(:alice).id, title: "Hello", id: 424242, created_at: 1.year.ago)

    assert outcome.valid?
    assert_not_equal 424242, outcome.result.id
    assert_in_delta Time.current, outcome.result.created_at, 1.minute
  end

  test "find raises for a missing post" do
    assert_raises(ActiveRecord::RecordNotFound) { Posts::Find.run(id: 0) }
  end

  test "update changes only the attributes that were passed" do
    outcome = Posts::Update.run(actor:, id: @post.id, published: true)

    assert outcome.valid?
    assert_equal true, @post.reload.published
    assert_equal "MyString", @post.title
  end

  test "update can clear a nullable attribute" do
    assert Posts::Update.run(actor:, id: @post.id, body: nil).valid?
    assert_nil @post.reload.body
  end

  test "update reports validation errors and persists nothing" do
    outcome = Posts::Update.run(actor:, id: @post.id, title: "x" * (Post::TITLE_MAX_LENGTH + 1))

    assert_not outcome.valid?
    assert outcome.errors.of_kind?(:title, :too_long)
    assert_equal "MyString", @post.reload.title
  end

  test "update raises for a missing post" do
    assert_raises(ActiveRecord::RecordNotFound) { Posts::Update.run(actor:, id: 0, title: "x") }
  end

  test "destroy removes the post" do
    assert_difference("Post.count", -1) { Posts::Destroy.run!(actor:, id: @post.id) }
  end

  test "destroy raises for a missing post" do
    assert_raises(ActiveRecord::RecordNotFound) { Posts::Destroy.run(actor:, id: 0) }
  end

  private

  def actor
    Actor.new(user_id: users(:alice).id)
  end
end
