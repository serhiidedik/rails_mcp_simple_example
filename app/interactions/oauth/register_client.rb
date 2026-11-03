module Oauth
  # Dynamic Client Registration (RFC 7591). The MCP spec deprecates it in favor of Client ID
  # Metadata Documents and keeps it for backwards compatibility, so existing clients still work.
  #
  # Anyone can call this, which makes the result untrusted: only public clients are created,
  # PKCE stays mandatory, and the consent page labels the client as unverified.
  class RegisterClient < ApplicationInteraction
    DEFAULT_NAME = "Unnamed MCP client"
    MAX_NAME_LENGTH = 200
    MAX_REDIRECT_URIS = 10

    string :client_name, default: nil
    array :redirect_uris, default: [] do
      string
    end

    validates :client_name, length: { maximum: MAX_NAME_LENGTH }, allow_nil: true
    validate :redirect_uris_are_acceptable

    def execute
      application = Doorkeeper::Application.new(
        name: client_name.presence || DEFAULT_NAME,
        redirect_uri: redirect_uris.join("\n"),
        confidential: false,
        registration_type: "dynamic"
      )
      errors.merge!(application.errors) unless application.save
      application
    end

    private

    def redirect_uris_are_acceptable
      if redirect_uris.empty? || redirect_uris.size > MAX_REDIRECT_URIS
        errors.add(:redirect_uris, "must list between 1 and #{MAX_REDIRECT_URIS} URIs")
      elsif !redirect_uris.all? { |uri| RedirectUriPolicy.allowed?(uri) }
        errors.add(:redirect_uris, "must use https, or http on a loopback host")
      end
    end
  end
end
