require "test_helper"

class Posts::ListTest < ActiveSupport::TestCase
  setup { Post.destroy_all }

  test "returns the newest posts first and walks every page through the cursor" do
    created = Array.new(5) { |i| Post.create!(title: "Post #{i}") }

    first = Posts::List.run!(limit: 2)
    assert_equal created.last(2).reverse, first.records
    assert first.next_cursor

    second = Posts::List.run!(limit: 2, cursor: first.next_cursor)
    assert_equal created[1..2].reverse, second.records

    last = Posts::List.run!(limit: 2, cursor: second.next_cursor)
    assert_equal [ created.first ], last.records
    assert_nil last.next_cursor
  end

  test "runs a single query however many rows the page holds" do
    3.times { |i| Post.create!(title: "Post #{i}") }

    assert_queries_count(1) { Posts::List.run!(limit: 2) }
  end

  test "rejects a limit outside the allowed range" do
    assert_not Posts::List.run(limit: 0).valid?
    assert_not Posts::List.run(limit: Posts::List::MAX_LIMIT + 1).valid?
  end

  test "rejects malformed and out-of-range cursors" do
    [ "not base64!", Base64.urlsafe_encode64("abc"), Base64.urlsafe_encode64("-1"),
      Base64.urlsafe_encode64((2**64).to_s) ].each do |cursor|
      outcome = Posts::List.run(cursor:)

      assert_not outcome.valid?, "expected #{cursor.inspect} to be rejected"
      assert outcome.errors.include?(:cursor)
    end
  end
end
