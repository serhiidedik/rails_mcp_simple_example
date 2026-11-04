Rails.application.routes.draw do
  # MCP over Streamable HTTP. The lambda keeps the endpoint reloadable in development.
  match Rails.configuration.x.mcp.endpoint_path, to: ->(env) { McpEndpoint.call(env) }, via: :all

  # OAuth 2.1 authorization server, plus /.well-known/oauth-authorization-server (RFC 8414).
  # Only what the MCP flow needs is routed: no admin UI, no token info.
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations"
    skip_controllers :applications, :authorized_applications, :token_info
  end

  # Plain POST routes for what a form submits. An API-only app has no Rack::MethodOverride, so a
  # form asking for DELETE through `_method` would be routed by its POST: on the consent page,
  # "Deny" would grant access.
  scope :oauth, module: :oauth, as: :oauth do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    post "logout", to: "sessions#destroy"
    post "authorize/deny", to: "authorizations#destroy", as: :deny
    post "register", to: "client_registrations#create"
  end

  # Ids are digits only, so anything else stays a 404 instead of an input error.
  resources :posts, constraints: { id: /\d+/ }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Browsers ask for this on every first visit. Answering keeps a routing error out of the logs.
  get "favicon.ico", to: ->(_env) { [ 204, { "cache-control" => "public, max-age=86400" }, [] ] }

  # Defines the root path route ("/")
  # root "posts#index"
end
