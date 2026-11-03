Rails.application.routes.draw do
  # OAuth 2.1 authorization server, plus /.well-known/oauth-authorization-server (RFC 8414).
  # Only what the MCP flow needs is routed: no admin UI, no token info.
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations"
    skip_controllers :applications, :authorized_applications, :token_info
  end

  scope :oauth, module: :oauth, as: :oauth do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"
    post "register", to: "client_registrations#create"
  end

  # Ids are digits only, so anything else stays a 404 instead of an input error.
  resources :posts, constraints: { id: /\d+/ }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
