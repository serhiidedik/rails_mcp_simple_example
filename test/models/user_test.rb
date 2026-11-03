require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes the email address" do
    assert_equal "someone@example.com", User.new(email_address: " SomeOne@Example.COM ").email_address
  end

  test "requires a valid, unique email address and a long enough password" do
    assert_not User.new(email_address: "nope", password: OauthTestHelpers::PASSWORD).valid?
    assert_not User.new(email_address: users(:alice).email_address.upcase, password: OauthTestHelpers::PASSWORD).valid?
    assert_not User.new(email_address: "new@example.com", password: "short").valid?
    assert User.new(email_address: "new@example.com", password: OauthTestHelpers::PASSWORD).valid?
  end

  test "deleting a user removes their grants and tokens" do
    tokens = obtain_tokens_without_http(users(:alice))

    users(:alice).destroy!

    assert_nil Doorkeeper::AccessToken.by_token(tokens)
  end

  private

  def obtain_tokens_without_http(user)
    Doorkeeper::AccessToken.create!(application: create_public_client, resource_owner_id: user.id, scopes: "posts:read", expires_in: 3600).plaintext_token
  end
end
