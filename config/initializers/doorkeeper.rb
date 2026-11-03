# OAuth 2.1 authorization server, configured for the MCP authorization spec:
# https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization
mcp = Rails.configuration.x.mcp

Doorkeeper.configure do
  orm :active_record

  # --- Who approves: browser login and consent pages -------------------------------------
  base_controller "Oauth::BrowserController"

  resource_owner_authenticator { authenticate_user_or_redirect_to_login }

  # Refuse an unknown client or a bad redirect URI before asking anyone to log in.
  validate_client_before_resource_owner_authentication

  # Report errors to the client through its validated redirect URI, with the `iss` parameter.
  handle_auth_errors :redirect

  # --- What is issued ---------------------------------------------------------------------
  # Authorization code only: no implicit, password or client credentials grants.
  grant_flows %w[ authorization_code ]

  # S256 PKCE on every client; `plain` would give no protection against interception.
  force_pkce
  pkce_code_challenge_methods %w[ S256 ]

  # Short-lived access tokens; refresh tokens rotate on every use.
  authorization_code_expires_in 5.minutes
  access_token_expires_in 1.hour
  use_refresh_token

  # A database leak must not yield usable credentials: only digests are stored.
  hash_token_secrets
  hash_application_secrets using: "::Doorkeeper::SecretStoring::BCrypt"

  # `none` is the public client. Secrets are only accepted in the Authorization header.
  client_authentication :client_secret_basic, :none

  # --- Scopes -----------------------------------------------------------------------------
  default_scopes "posts:read"
  optional_scopes "posts:write", "posts:delete"
  enforce_configured_scopes

  # --- Audience binding (RFC 8707) --------------------------------------------------------
  # Tokens are issued only for this server's MCP endpoint, and record it.
  resource_indicator_validator ->(resources, _client) { resources.all? { |uri| Oauth::ResourceIndicator.canonical?(uri) } }

  # --- Redirect URIs ----------------------------------------------------------------------
  force_ssl_in_redirect_uri { |uri| !Oauth::RedirectUriPolicy.loopback?(uri) }
  forbid_redirect_uri { |uri| !Oauth::RedirectUriPolicy.allowed?(uri.to_s) }

  # --- Discovery (RFC 8414, RFC 9207) ----------------------------------------------------
  # The issuer also turns on the `iss` parameter in authorization responses.
  issuer mcp.public_url
  custom_metadata({
    registration_endpoint: "#{mcp.public_url}/oauth/register",
    client_id_metadata_document_supported: true,
    # Oauth::AuthorizationsController ignores any other mode.
    response_modes_supported: %w[ query ]
  })

  # Nothing here needs introspection: the resource server reads the same database.
  allow_token_introspection false
end
