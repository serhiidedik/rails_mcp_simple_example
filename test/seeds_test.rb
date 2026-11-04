require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "development gets a demo user and unique sample posts, once" do
    Post.delete_all

    assert_difference -> { User.count } => 1, -> { Post.count } => 10 do
      seed_as_development
    end
    assert_equal 10, Post.distinct.count(:title)
    assert_equal 10, Post.distinct.count(:body)
    assert Post.all.all?(&:valid?)

    assert_no_difference [ "User.count", "Post.count" ] do
      seed_as_development
    end
  end

  test "other environments get nothing" do
    assert_no_difference [ "User.count", "Post.count" ] do
      Rails.application.load_seed
    end
  end

  private

  def seed_as_development
    original = Rails.env
    Rails.env = "development"
    capture_io { Rails.application.load_seed }
  ensure
    Rails.env = original
  end
end
