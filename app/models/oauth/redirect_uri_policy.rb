module Oauth
  # "All redirect URIs MUST be either localhost or use HTTPS" (MCP authorization spec).
  # Custom schemes, fragments and embedded credentials are refused for every client.
  module RedirectUriPolicy
    LOOPBACK_HOSTS = %w[ localhost 127.0.0.1 ::1 ].freeze

    module_function

    def allowed?(value)
      uri = URI.parse(value.to_s)
      return false if uri.host.blank? || uri.fragment || uri.userinfo

      uri.scheme == "https" || (uri.scheme == "http" && loopback?(uri))
    rescue URI::InvalidURIError
      false
    end

    def loopback?(uri)
      LOOPBACK_HOSTS.include?(uri.hostname)
    end
  end
end
