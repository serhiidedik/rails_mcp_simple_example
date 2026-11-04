# The MCP server is an OAuth resource server. The per-request wiring lives in McpEndpoint;
# this file holds what is decided once at boot.
settings = Rails.configuration.x.mcp

# Fail at boot, not on the first client: every challenge and token check depends on this URL.
raise "MCP_PUBLIC_URL is required (the public https URL of this app, no trailing slash)" if settings.public_url.blank?

# RFC 9728. The SDK refuses non-https URLs outside loopback, so a misconfiguration fails here too.
settings.resource_metadata = MCP::Server::OAuth::ProtectedResourceMetadata.new(
  resource: settings.resource_uri,
  authorization_servers: [ settings.public_url ],
  # Every scope, so that one consent covers every tool. Clients ask for what this lists.
  scopes_supported: Doorkeeper.config.scopes.to_a,
  resource_name: settings.server_title
)

# Served above any authentication: this document is how a client without a token starts.
Rails.application.config.middleware.use(
  MCP::Server::OAuth::ProtectedResourceMetadataMiddleware,
  settings.resource_metadata
)

MCP.configure do |config|
  # The SDK's context includes the raw request body, so it is not passed on: tool arguments
  # can hold user content and do not belong in an error tracker. A scope shortfall is a
  # normal client error, not something to report.
  config.exception_reporter = lambda do |exception, _context|
    next if exception.is_a?(MCP::Server::OAuth::Error)

    Rails.error.report(exception, handled: true, source: "mcp")
  end
end
