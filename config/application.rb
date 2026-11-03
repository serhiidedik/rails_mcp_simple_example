require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsMcpSimpleExample
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Public URL of the MCP endpoint and of the OAuth issuer (config/mcp.yml).
    config.x.mcp = config_for(:mcp)
    config.x.mcp.resource_uri = "#{config.x.mcp.public_url}#{config.x.mcp.endpoint_path}"

    # The API itself stays stateless. Only the OAuth login and consent pages use a session,
    # so its cookie is scoped to /oauth and never reaches /mcp or the REST endpoints.
    config.session_store :cookie_store,
      key: "_mcp_oauth_session",
      path: "/oauth",
      same_site: :lax,
      secure: Rails.env.production?,
      expire_after: 1800 # seconds: long enough to approve a client, short on a shared machine.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    # A client-controlled Client-Ip header must never become a 500: remote_ip is read inside
    # the rack-attack middleware, before any rescue_from can run.
    config.action_dispatch.ip_spoofing_check = false
  end
end
