# Rate limits, in one place, for every endpoint including the ones Doorkeeper owns.
class Rack::Attack
  # The real client behind the proxies, resolved by Rails. The raw req.ip is the proxy.
  class Request < ::Rack::Request
    def remote_ip
      ActionDispatch::Request.new(env).remote_ip
    end

    def login_email
      params["email_address"].to_s.strip.downcase.presence if post? && path == "/oauth/login"
    rescue Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, EOFError
      nil
    end

    def bearer_token_digest
      header = get_header("HTTP_AUTHORIZATION")
      Digest::SHA256.hexdigest(header) if header.present?
    end
  end

  # Counters are shared by every Puma worker and server in production: a per-process store
  # would multiply each limit by the size of the fleet.
  self.cache.store = Rails.env.production? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new

  # Tests switch it on where they need it, so the suite does not trip over its own limits.
  self.enabled = !Rails.env.test?

  safelist("healthcheck") { |req| req.path == "/up" }

  # Rails parses these bodies before any controller code could limit them.
  blocklist("oversized oauth requests") do |req|
    req.path.start_with?("/oauth/") && req.content_length.to_i > 64.kilobytes
  end

  # A floor for everything.
  throttle("req/ip", limit: ENV.fetch("RATE_LIMIT_REQ_IP", 600).to_i, period: 5.minutes, &:remote_ip)

  # A runaway agent, or a stolen token, wherever it calls from.
  throttle("mcp/token", limit: 120, period: 1.minute) do |req|
    req.bearer_token_digest if req.path == Rails.configuration.x.mcp.endpoint_path
  end

  # Password guessing: from one address, and against one account from many addresses.
  throttle("oauth/login/ip", limit: ENV.fetch("RATE_LIMIT_LOGIN_IP", 10).to_i, period: 1.minute) do |req|
    req.remote_ip if req.post? && req.path == "/oauth/login"
  end
  throttle("oauth/login/email", limit: 10, period: 5.minutes, &:login_email)

  # Guessing codes and refresh tokens.
  throttle("oauth/token/ip", limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.post? && [ "/oauth/token", "/oauth/revoke" ].include?(req.path)
  end

  # Open registration writes rows.
  throttle("oauth/register/ip", limit: 10, period: 1.hour) do |req|
    req.remote_ip if req.post? && req.path == "/oauth/register"
  end

  # A URL-shaped client_id makes this server fetch that URL.
  throttle("oauth/authorize/ip", limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path == "/oauth/authorize"
  end

  self.throttled_responder = lambda do |request|
    headers = {
      "content-type" => "application/json",
      "cache-control" => "no-store",
      "retry-after" => request.env["rack.attack.match_data"][:period].to_s
    }

    [ 429, headers, [ { error: "rate_limited" }.to_json ] ]
  end
end
