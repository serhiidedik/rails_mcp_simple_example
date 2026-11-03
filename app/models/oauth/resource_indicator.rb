module Oauth
  # The canonical URI of this server's MCP endpoint, which every token is bound to (RFC 8707).
  # Scheme and host compare case-insensitively, as the spec asks; everything else is exact.
  module ResourceIndicator
    module_function

    def canonical
      Rails.configuration.x.mcp.resource_uri
    end

    def canonical?(value)
      normalize(value) == normalize(canonical)
    rescue URI::InvalidURIError
      false
    end

    def normalize(value)
      URI.parse(value.to_s).normalize.to_s
    end
    private_class_method :normalize
  end
end
