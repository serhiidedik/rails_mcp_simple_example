# The single seam between the MCP resource server and the authorization server: token in,
# verified identity out. To move to an external provider (Keycloak, Auth0, ...), replace this
# class with the SDK's MCP::Server::OAuth::JWTVerifier or IntrospectionVerifier in McpEndpoint.
class DoorkeeperTokenVerifier < MCP::Server::OAuth::TokenVerifier
  InvalidToken = MCP::Server::OAuth::InvalidTokenError

  # The same answer for every rejection, so a caller cannot probe which tokens exist.
  REJECTION = "The access token is invalid".freeze

  def initialize(issuer:)
    super()
    @issuer = issuer
  end

  def verify(raw_token)
    token = Doorkeeper::AccessToken.by_token(raw_token)
    raise InvalidToken, REJECTION unless token&.accessible? && issued_for_this_server?(token)

    MCP::Server::OAuth::AccessToken.new(
      token: raw_token,
      client_id: token.application&.uid,
      scopes: token.scopes.to_a,
      expires_at: token.expires_at&.to_i,
      subject: token.resource_owner_id.to_s,
      issuer: @issuer,
      audience: token.resource,
      resource: Oauth::ResourceIndicator.canonical
    )
  end

  private

  # RFC 8707: a valid token issued for anything else must not work here.
  def issued_for_this_server?(token)
    token.resource.to_s.split.any? { |resource| Oauth::ResourceIndicator.canonical?(resource) }
  end
end
