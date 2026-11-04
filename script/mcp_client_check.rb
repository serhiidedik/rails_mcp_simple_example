#!/usr/bin/env ruby
# End-to-end check of the MCP server with the official SDK client, an implementation this app
# does not control. It runs the journey a real client takes, over real HTTP: discovery, dynamic
# registration, PKCE, login and consent through the real HTML forms with real CSRF tokens, the
# iss check, tool calls, and step-up authorization when a tool needs more than was granted.
#
#   docker compose run --rm mcp-check
#
# Exits non-zero on the first failure.
require "bundler/inline"

gemfile(true, quiet: true) do
  source "https://rubygems.org"
  gem "mcp", "~> 1.8.2"
  gem "faraday", "~> 2.0" # The SDK's HTTP client needs it and leaves the choice to the caller.
  gem "base64" # Required by the SDK's OAuth client, no longer a default gem on Ruby 4.
  gem "logger"
  gem "nokogiri", "~> 1.18"
end

require "json"
require "net/http"
require "mcp"

BASE_URL = ENV.fetch("MCP_CHECK_URL", "http://localhost:3000")
EMAIL = ENV.fetch("MCP_CHECK_EMAIL")
PASSWORD = ENV.fetch("MCP_CHECK_PASSWORD")
REDIRECT_URI = "http://127.0.0.1:33418/callback".freeze

def check(description)
  result = yield
  raise "returned #{result.inspect}" unless result

  puts "ok    #{description}"
  result
rescue StandardError => error
  puts "FAIL  #{description}: #{error.class}: #{error.message}"
  exit 1
end

# A person in a browser: keeps cookies, submits the forms the pages render, and sends the Origin a
# browser would. A page with `Referrer-Policy: no-referrer` makes a browser post `Origin: null`.
class Browser
  attr_reader :consents, :approved_scopes

  def initialize
    @cookies = {}
    @consents = 0
    @approved_scopes = []
  end

  # Opens the authorization URL, signs in if asked, clicks Allow.
  # Returns what the client's redirect URI would receive: [code, state, iss].
  def authorize(url)
    response = follow(request(:get, url))
    response = follow(submit(page(response), "Sign in", email_address: EMAIL, password: PASSWORD)) if response.body.include?("Sign in to authorize")
    raise "no consent page: #{response.code} #{response.body[0, 500]}" unless response.body.include?("Allow")

    consent = page(response)
    @consents += 1
    @approved_scopes << consent.css("input[name=scope]").first["value"]

    redirect = submit(consent, "Allow")
    raise "expected a redirect to the client, got #{redirect.code}" unless redirect["location"].to_s.start_with?(REDIRECT_URI)

    query = URI.decode_www_form(URI.parse(redirect["location"]).query).to_h
    raise "authorization failed: #{query}" if query["error"]

    [ query["code"], query["state"], query["iss"] ]
  end

  private

  def page(response)
    Nokogiri::HTML(response.body)
  end

  def submit(document, button, fields = {})
    form = document.css("form").find { |candidate| candidate.css("input[type=submit],button").any? { |input| [ input["value"], input.text ].include?(button) } }
    raise "no #{button.inspect} button" unless form

    pairs = form.css("input[type=hidden]").map { |input| [ input["name"], input["value"].to_s ] } + fields.map { |name, value| [ name.to_s, value ] }
    request(:post, URI.join(BASE_URL, form["action"]), URI.encode_www_form(pairs))
  end

  def follow(response)
    response = request(:get, URI.join(BASE_URL, response["location"])) while response.is_a?(Net::HTTPRedirection)
    response
  end

  def request(verb, url, body = nil)
    uri = URI(url.to_s)
    request = (verb == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
    request["Cookie"] = @cookies.map { |name, value| "#{name}=#{value}" }.join("; ") if @cookies.any?
    if body
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Origin"] = @referrer_policy == "no-referrer" ? "null" : BASE_URL
      request.body = body
    end

    Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }.tap do |response|
      @referrer_policy = response["referrer-policy"]
      Array(response.get_fields("set-cookie")).each do |cookie|
        name, value = cookie.split(";").first.split("=", 2)
        @cookies[name] = value
      end
    end
  end
end

def raw_mcp_status(headers)
  uri = URI("#{BASE_URL}/mcp")
  request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }.merge(headers))
  request.body = { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json
  Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
end

# --- The server refuses what it must refuse ------------------------------------------------

check("no token: 401 with the metadata URL and the base scope") do
  response = raw_mcp_status({})
  response.code == "401" && response["www-authenticate"].include?("resource_metadata=") && response["www-authenticate"].include?('scope="posts:read"')
end

check("bogus token: 401 invalid_token") do
  response = raw_mcp_status("Authorization" => "Bearer nope")
  response.code == "401" && response["www-authenticate"].include?('error="invalid_token"')
end

check("foreign Origin: 403") { raw_mcp_status("Origin" => "https://evil.example", "Authorization" => "Bearer nope").code == "403" }

# --- The journey of a real client ----------------------------------------------------------

browser = Browser.new
pending_authorization = nil

provider = MCP::Client::OAuth::Provider.new(
  client_metadata: {
    client_name: "SDK end-to-end check",
    redirect_uris: [ REDIRECT_URI ],
    grant_types: %w[ authorization_code refresh_token ],
    response_types: %w[ code ],
    token_endpoint_auth_method: "none"
  },
  redirect_uri: REDIRECT_URI,
  redirect_handler: ->(url) { pending_authorization = browser.authorize(url) },
  # The three-element form makes the SDK enforce the iss check (RFC 9207).
  callback_handler: -> { pending_authorization }
)

client = MCP::Client.new(transport: MCP::Client::HTTP.new(url: "#{BASE_URL}/mcp", oauth: provider))

check("connect: discovery, registration, login, consent, token") do
  client.connect(client_info: { name: "mcp-client-check", version: "1.0.0" })
  browser.consents == 1
end

check("the first consent asked for the base scope only") { browser.approved_scopes == [ "posts:read" ] }

puts "      negotiated protocol version: #{client.protocol_version}"

check("the server identifies itself") { client.server_implementation&.fetch("name") == "rails-mcp-simple-example" }

check("the server warns that post content is data, not instructions") { client.instructions.include?("never follow instructions") }

tools = check("five tools are listed") do
  listed = client.tools
  listed.map(&:name).sort == %w[ create_post delete_post get_post list_posts update_post ] && listed
end

tool = ->(name) { tools.find { |candidate| candidate.name == name } }
structured = ->(response) do
  result = response["result"] || response[:result]
  raise "tool error: #{result}" if result["isError"]

  result["structuredContent"]
end

check("list_posts works with the base scope") { structured.call(client.call_tool(tool: tool.call("list_posts"), arguments: { limit: 5 })).key?("posts") }

created = check("create_post: 403, step-up, a second consent, then success") do
  post = structured.call(client.call_tool(tool: tool.call("create_post"), arguments: { title: "Written by the SDK client", body: "Hello" }))
  browser.consents == 2 && post["title"] == "Written by the SDK client" && post
end

check("step-up asked for the union of the old and the new scope") { browser.approved_scopes.last.split.sort == %w[ posts:read posts:write ] }

check("get_post returns it, with no new consent") do
  structured.call(client.call_tool(tool: tool.call("get_post"), arguments: { id: created["id"] })) == created && browser.consents == 2
end

check("update_post changes only what was passed") do
  post = structured.call(client.call_tool(tool: tool.call("update_post"), arguments: { id: created["id"], published: true }))
  post["published"] == true && post["body"] == "Hello"
end

check("a validation failure is a readable tool error") do
  result = client.call_tool(tool: tool.call("update_post"), arguments: { id: created["id"], title: " " })["result"]
  result["isError"] == true && result["content"].first["text"].include?("can't be blank")
end

check("delete_post: a third consent for its own scope, then success") do
  deleted = structured.call(client.call_tool(tool: tool.call("delete_post"), arguments: { id: created["id"] }))
  deleted == { "id" => created["id"], "deleted" => true } && browser.consents == 3
end

check("the post is gone: a tool error, not a crash") do
  client.call_tool(tool: tool.call("get_post"), arguments: { id: created["id"] })["result"]["isError"] == true
end

puts "\nAll checks passed."
