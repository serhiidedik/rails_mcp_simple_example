# The public reference at GET /: what Swagger UI is to a REST API. It is rendered from the tool
# classes on every request, so it cannot disagree with what the server does.
#
# It holds no data and reads none, and it runs no script: this page shares an origin with the
# consent page, so a third-party script here could reach the sign-in session. Hence no CDN, and a
# policy that forbids everything except its own inline styles. To keep the contract private,
# remove these two routes.
class DocsController < ActionController::Base
  CONTENT_SECURITY_POLICY = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'".freeze

  layout "docs"

  before_action :set_security_headers

  def show
    @reference = McpApiReference.new
  end

  def tools
    render json: McpApiReference.new.tools_document
  end

  private

  def set_security_headers
    response.headers["Content-Security-Policy"] = CONTENT_SECURITY_POLICY
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
