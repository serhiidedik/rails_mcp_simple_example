# frozen_string_literal: true

class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string  :name,    null: false
      t.string  :uid,     null: false
      # Nullable: self-registered MCP clients are public clients and have no secret.
      t.string  :secret

      # Remove `null: false` if you are planning to use grant flows
      # that doesn't require redirect URI to be used during authorization
      # like Client Credentials flow or Resource Owner Password.
      t.text    :redirect_uri, null: false
      t.string  :scopes,       null: false, default: ''
      t.boolean :confidential, null: false, default: true
      # How the client got here: manual, dynamic (RFC 7591) or metadata_document (CIMD).
      # Only self-registered clients are ever purged.
      t.string  :registration_type, null: false, default: "manual"
      t.timestamps null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner,  null: false
      t.references :application,     null: false
      t.string   :token,             null: false
      t.integer  :expires_in,        null: false
      t.text     :redirect_uri,      null: false
      t.string   :scopes,            null: false, default: ''
      t.datetime :created_at,        null: false
      t.datetime :revoked_at

      # Authorization codes are single-use (RFC 6749 §4.1.2). Doorkeeper
      # records the access token issued when the code is exchanged, so that
      # a second exchange attempt revokes the previously issued tokens as
      # recommended by RFC 6749 §10.5.
      #
      # Comment out this line if you don't want a reused authorization code
      # to revoke the tokens already issued for it.
      #
      # Indexed: when a code is replayed, the revocation checks whether the
      # issued token is still referenced by another grant, which filters
      # this table by access_token_id.
      t.references :access_token,    index: true
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key(
      :oauth_access_grants,
      :oauth_applications,
      column: :application_id
    )

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true

      # Remove `null: false` if you are planning to use Password
      # Credentials Grant flow that doesn't require an application.
      t.references :application,    null: false

      # If you use a custom token generator you may need to change this column
      # from string to text, so that it accepts tokens larger than 255
      # characters. More info on custom token generators in:
      # https://github.com/doorkeeper-gem/doorkeeper/tree/v3.0.0.rc1#custom-access-token-generator
      #
      # t.text :token, null: false
      t.string :token, null: false

      t.string   :refresh_token
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at

      # No `previous_refresh_token` column on purpose: without it Doorkeeper revokes a
      # refresh token the moment it is used, which is the strict rotation public clients
      # need. The cost is that a client losing the response has to authorize again.

      # A refresh token keeps the scope originally granted by the resource
      # owner, so a client that narrowed an access token on one refresh can
      # request the granted scope again on the next one.
      # @see https://datatracker.ietf.org/doc/html/rfc6749#section-6
      #
      # Comment out this line if you want a narrowed refresh to permanently
      # narrow the refresh token as well.
      t.string   :refresh_token_scopes
    end

    add_index :oauth_access_tokens, :token, unique: true

    # See https://github.com/doorkeeper-gem/doorkeeper/issues/1592
    if ActiveRecord::Base.connection.adapter_name == "SQLServer"
      execute <<~SQL.squish
        CREATE UNIQUE NONCLUSTERED INDEX index_oauth_access_tokens_on_refresh_token ON oauth_access_tokens(refresh_token)
        WHERE refresh_token IS NOT NULL
      SQL
    else
      add_index :oauth_access_tokens, :refresh_token, unique: true
    end

    add_foreign_key(
      :oauth_access_tokens,
      :oauth_applications,
      column: :application_id
    )

    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id
  end
end
