require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  DEMO_USER = { "SEED_USER_EMAIL" => "seed-test@example.com", "SEED_USER_PASSWORD" => "a-long-enough-password" }.freeze

  test "development gets the configured demo user and unique sample posts, once" do
    Post.destroy_all

    assert_difference -> { User.count } => 1, -> { Post.count } => 10, -> { Comment.count } => 30 do
      capture_io { seed_as_development(DEMO_USER) }
    end
    assert User.authenticate_by(email_address: DEMO_USER["SEED_USER_EMAIL"], password: DEMO_USER["SEED_USER_PASSWORD"])
    assert_equal 10, Post.distinct.count(:title)
    assert_equal 10, Post.distinct.count(:body)
    assert Post.all.all?(&:valid?)
    assert Post.all.all? { |post| post.comments.size == 3 }
    assert Comment.all.all?(&:valid?)

    assert_no_difference [ "User.count", "Post.count", "Comment.count" ] do
      capture_io { seed_as_development(DEMO_USER) }
    end
  end

  test "posts that already exist get comments too" do
    Comment.delete_all

    assert_no_difference("Post.count") do
      assert_difference("Comment.count", Post.count * 3) { capture_io { seed_as_development(DEMO_USER) } }
    end
  end

  test "development refuses to seed without the demo credentials, and says what to do" do
    [ {}, DEMO_USER.merge("SEED_USER_PASSWORD" => ""), DEMO_USER.merge("SEED_USER_EMAIL" => " ") ].each do |env|
      assert_no_difference [ "User.count", "Post.count" ] do
        _, stderr = capture_io do
          assert_raises(SystemExit) { seed_as_development(env) }
        end
        assert_includes stderr, ".env.example"
      end
    end
  end

  test "other environments get nothing" do
    assert_no_difference [ "User.count", "Post.count" ] do
      Rails.application.load_seed
    end
  end

  test "the demo credentials in .env.example make a valid account" do
    values = Rails.root.join(".env.example").readlines(chomp: true).filter_map { |line| line.split("=", 2) if line.match?(/\A[A-Z_]+=/) }.to_h

    assert_predicate User.new(email_address: values.fetch("SEED_USER_EMAIL"), password: values.fetch("SEED_USER_PASSWORD")), :valid?
  end

  private

  def seed_as_development(env)
    original_env = Rails.env
    original_values = DEMO_USER.keys.to_h { |name| [ name, ENV[name] ] }
    original_values.each_key { |name| ENV[name] = env[name] }
    Rails.env = "development"
    Rails.application.load_seed
  ensure
    Rails.env = original_env
    original_values.each { |name, value| ENV[name] = value }
  end
end
