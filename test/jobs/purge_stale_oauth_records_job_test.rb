require "test_helper"

class PurgeStaleOauthRecordsJobTest < ActiveJob::TestCase
  def token(application, **attributes)
    Doorkeeper::AccessToken.create!(application:, resource_owner_id: users(:alice).id, scopes: "posts:read", expires_in: 3600, **attributes)
  end

  test "removes revoked tokens and tokens past the retention, keeps live ones" do
    application = create_public_client
    live = token(application)
    expired_recently = token(application, created_at: 2.days.ago)
    revoked = token(application, revoked_at: 1.minute.ago)
    past_retention = token(application, created_at: 31.days.ago)

    PurgeStaleOauthRecordsJob.perform_now

    assert Doorkeeper::AccessToken.exists?(live.id)
    assert Doorkeeper::AccessToken.exists?(expired_recently.id), "its refresh token may still be in use"
    assert_not Doorkeeper::AccessToken.exists?(revoked.id)
    assert_not Doorkeeper::AccessToken.exists?(past_retention.id)
  end

  test "removes old grants" do
    application = create_public_client
    grant = Doorkeeper::AccessGrant.create!(application:, resource_owner_id: users(:alice).id, redirect_uri: application.redirect_uri, expires_in: 300, scopes: "posts:read", created_at: 2.days.ago)

    PurgeStaleOauthRecordsJob.perform_now

    assert_not Doorkeeper::AccessGrant.exists?(grant.id)
  end

  test "removes only self-registered clients nobody uses" do
    abandoned = create_public_client(registration_type: "dynamic")
    abandoned_document = create_public_client(registration_type: "metadata_document")
    recent = create_public_client(registration_type: "dynamic")
    in_use = create_public_client(registration_type: "dynamic")
    manual = create_public_client(registration_type: "manual")
    token(in_use)
    Doorkeeper::Application.where(id: [ abandoned, abandoned_document, in_use, manual ]).update_all(updated_at: 31.days.ago)

    PurgeStaleOauthRecordsJob.perform_now

    assert_not Doorkeeper::Application.exists?(abandoned.id)
    assert_not Doorkeeper::Application.exists?(abandoned_document.id)
    assert Doorkeeper::Application.exists?(recent.id)
    assert Doorkeeper::Application.exists?(in_use.id)
    assert Doorkeeper::Application.exists?(manual.id)
  end

  test "is scheduled in production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"))

    assert_equal "PurgeStaleOauthRecordsJob", recurring.dig("production", "purge_stale_oauth_records", "class")
  end
end
