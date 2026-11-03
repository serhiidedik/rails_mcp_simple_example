require "ipaddr"
require "net/http"

module Oauth
  # Fetches and validates an OAuth Client ID Metadata Document:
  # https://datatracker.ietf.org/doc/html/draft-ietf-oauth-client-id-metadata-document-00
  #
  # The URL comes from an unauthenticated request, so this is an SSRF surface. The defenses:
  # https on port 443 only, every resolved address must be public, the connection is pinned
  # to the checked address (no DNS rebinding between check and use), redirects and environment
  # proxies are not followed, and time and body size are bounded. Failure details are never
  # returned, so this cannot be used to probe a network.
  class FetchClientMetadataDocument < ApplicationInteraction
    MAX_URL_LENGTH = 2048
    MAX_BODY_BYTES = 5.kilobytes
    MAX_NAME_LENGTH = 200
    TIMEOUT_SECONDS = 3

    NON_PUBLIC_RANGES = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
      192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
      203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/96 64:ff9b::/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    NETWORK_ERRORS = [
      SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
      Net::ProtocolError, Net::HTTPBadResponse, JSON::ParserError, EncodingError
    ].freeze

    Unfetchable = Class.new(StandardError)
    private_constant :Unfetchable

    string :url, strip: false

    validate :url_is_acceptable

    def execute
      parse_document(read_body(uri, public_address_of(uri.hostname)))
    rescue Unfetchable, *NETWORK_ERRORS
      errors.add(:url, "could not be fetched as a valid client metadata document")
      nil
    end

    private

    def uri
      @uri ||= URI.parse(url)
    end

    def url_is_acceptable
      acceptable = url.length <= MAX_URL_LENGTH &&
        uri.scheme == "https" && uri.port == 443 && uri.host.present? &&
        uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
        uri.path.length > 1 && !uri.path.split("/").intersect?(%w[ . .. ])

      errors.add(:url, "is not an acceptable client id") unless acceptable
    rescue URI::InvalidURIError
      errors.add(:url, "is not an acceptable client id")
    end

    def public_address_of(hostname)
      addresses = resolve(hostname)
      raise Unfetchable if addresses.empty? || !addresses.all? { |address| public_address?(address) }

      addresses.first
    end

    def resolve(hostname)
      Addrinfo.getaddrinfo(hostname, 443, nil, :STREAM, timeout: TIMEOUT_SECONDS).map(&:ip_address).uniq
    end

    def public_address?(address)
      ip = IPAddr.new(address)
      ip = ip.native if ip.ipv4_mapped?
      NON_PUBLIC_RANGES.none? { |range| range.include?(ip) }
    rescue IPAddr::Error
      false
    end

    def read_body(uri, address)
      body = +""
      build_http(uri, address).start do |http|
        http.request(Net::HTTP::Get.new(uri, "Accept" => "application/json")) do |response|
          raise Unfetchable unless response.is_a?(Net::HTTPOK)

          response.read_body do |chunk|
            body << chunk
            raise Unfetchable if body.bytesize > MAX_BODY_BYTES
          end
        end
      end
      body
    end

    def build_http(uri, address)
      Net::HTTP.new(uri.host, uri.port, nil).tap do |http| # nil: ignore proxy environment variables.
        http.ipaddr = address
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = http.read_timeout = http.write_timeout = http.ssl_timeout = TIMEOUT_SECONDS
      end
    end

    def parse_document(body)
      document = JSON.parse(body, max_nesting: 8)
      raise Unfetchable unless valid_document?(document)

      { client_name: document["client_name"], redirect_uris: document["redirect_uris"] }
    end

    def valid_document?(document)
      document.is_a?(Hash) &&
        document["client_id"] == url && # Exact match: a document cannot speak for another URL.
        valid_name?(document["client_name"]) &&
        valid_redirect_uris?(document["redirect_uris"]) &&
        document.fetch("token_endpoint_auth_method", "none") == "none" &&
        !document.key?("client_secret")
    end

    def valid_name?(name)
      name.is_a?(String) && name.strip.present? && name.length <= MAX_NAME_LENGTH
    end

    def valid_redirect_uris?(uris)
      uris.is_a?(Array) && uris.any? && uris.size <= RegisterClient::MAX_REDIRECT_URIS &&
        uris.all? { |uri| uri.is_a?(String) && RedirectUriPolicy.allowed?(uri) }
    end
  end
end
