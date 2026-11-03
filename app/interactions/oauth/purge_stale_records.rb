module Oauth
  # Retention sweep. TOKEN_RETENTION is also the longest a client can stay idle:
  # a refresh token is deleted with its access token, and each rotation starts a new record.
  class PurgeStaleRecords < ApplicationInteraction
    TOKEN_RETENTION = 30.days
    GRANT_RETENTION = 1.day
    ABANDONED_CLIENT_AGE = 30.days
    SELF_REGISTERED_TYPES = [ "dynamic", ResolveMetadataDocumentClient::REGISTRATION_TYPE ].freeze

    def execute
      purge(Doorkeeper::AccessToken, TOKEN_RETENTION)
      purge(Doorkeeper::AccessGrant, GRANT_RETENTION)
      abandoned_clients.find_each(&:destroy!)
    end

    private

    def purge(model, retention)
      cleaner = Doorkeeper::StaleRecordsCleaner.new(model)
      cleaner.clean_revoked
      cleaner.clean_expired(retention)
    end

    # Self-registered clients nobody ever approved, or whose tokens have all been purged.
    # Registration is open to anyone, so these rows must not accumulate forever.
    def abandoned_clients
      Doorkeeper::Application
        .where(registration_type: SELF_REGISTERED_TYPES, updated_at: ...ABANDONED_CLIENT_AGE.ago)
        .where.missing(:access_tokens, :access_grants)
    end
  end
end
