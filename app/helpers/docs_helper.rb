# The call-flow diagrams on the reference page, as data. Each step is one line of a sequence
# chart, between two of the lanes. `outcome` is how that step can refuse the request.
#
# These describe app/mcp and the SDK transport by hand: keep them in step with the code, and
# with the Mermaid versions in README.md.
module DocsHelper
  # A version already past the dependency cooldown, and the one this page was checked against.
  INSPECTOR_VERSION = "2.12.0".freeze

  Step = Data.define(:from, :to, :text, :outcome, :reply) do
    def self.call(from, to, text, outcome: nil, reply: false)
      new(from:, to:, text:, outcome:, reply:)
    end

    def self_check? = from == to
    def start = [ from, to ].min
    def finish = [ from, to ].max
    def span = finish - start + 1
    def leftward? = to < from
  end

  TOOL_CALL = {
    caption: "How one tool call travels from the client to the database and back",
    lanes: [ "Client", "Rails", "Transport", "Tool", "Interaction", "Post" ],
    steps: [
      Step.call(1, 2, "`POST /mcp` with `tools/call get_post` and a bearer token"),
      Step.call(2, 2, "Is the Host this app's, in production? Is the caller within its rate limits?", outcome: "Refused with 403 or 429"),
      Step.call(2, 3, "`McpEndpoint` builds a server and transport for this one request"),
      Step.call(3, 3, "Are Origin and Host allowed?", outcome: "Refused with 403"),
      Step.call(3, 3, "`DoorkeeperTokenVerifier`: is the token known, unexpired, not revoked and issued for this endpoint?", outcome: "Refused with 401"),
      Step.call(3, 3, "Does the token hold `posts:read`, the scope of this tool?", outcome: "Refused with 403, naming the scope"),
      Step.call(3, 3, "Does the tool exist, and do the arguments match its `inputSchema`?", outcome: "Refused with -32602, or reported with isError"),
      Step.call(3, 4, "`GetTool.call(id: 1)` checks the scope again and starts the audit line"),
      Step.call(4, 5, "`Posts::Find.run(id: 1)`"),
      Step.call(5, 6, "`Post.find(1)`", outcome: "If missing, reported with isError"),
      Step.call(6, 5, "The record", reply: true),
      Step.call(5, 4, "The outcome: a post, or validation errors", outcome: "Errors are reported with isError", reply: true),
      Step.call(4, 3, "`structuredContent` and a text copy. The audit line is written, and the SDK checks the result against `outputSchema`", reply: true),
      Step.call(3, 1, "`200` with the JSON-RPC result, marked `no-store`", reply: true)
    ]
  }.freeze

  FIRST_CONNECTION = {
    caption: "How a client gets its first token",
    lanes: [ "Person", "Client", "/mcp", "/oauth" ],
    steps: [
      Step.call(2, 3, "`POST /mcp` with no token"),
      Step.call(3, 2, "`401` with `resource_metadata`, and `scope` listing every scope", reply: true),
      Step.call(2, 3, "`GET /.well-known/oauth-protected-resource/mcp`"),
      Step.call(3, 2, "This resource and the server that authorizes it", reply: true),
      Step.call(2, 4, "`GET /.well-known/oauth-authorization-server`"),
      Step.call(4, 2, "The endpoints, and `S256` as the only PKCE method", reply: true),
      Step.call(2, 4, "`POST /oauth/register`, unless its `client_id` is a metadata URL"),
      Step.call(4, 2, "A `client_id`", reply: true),
      Step.call(2, 1, "Opens `/oauth/authorize` in a browser, with a PKCE challenge and `resource`"),
      Step.call(1, 4, "Signs in, reads the consent page and clicks Allow, once for every tool"),
      Step.call(4, 2, "Redirects to the client with `code`, `state` and `iss`"),
      Step.call(2, 4, "`POST /oauth/token` with the code, the verifier and `resource`"),
      Step.call(4, 2, "A 1-hour access token, and a refresh token that rotates on each use", reply: true),
      Step.call(2, 3, "Repeats the first request, with `Authorization: Bearer`")
    ]
  }.freeze

  # Turns `backticks` into <code>. Everything else is escaped.
  def inline_code(text)
    h(text).gsub(/`([^`]+)`/) { "<code>#{$1}</code>" }.html_safe
  end

  def step_style(step, lane_count)
    start_offset = (step.start - 1) * 100.0 / lane_count
    end_offset = (lane_count - step.finish) * 100.0 / lane_count

    "--span: #{step.span}; --column: #{step.start} / #{step.finish + 1}; --before: #{start_offset.round(2)}%; --after: #{end_offset.round(2)}%"
  end

  def step_classes(step, lane_count)
    classes = [ "step" ]
    classes << "check" if step.self_check?
    classes << "reply" if step.reply
    classes << "leftward" if step.leftward?
    classes << "from-right" if step.start > lane_count / 2
    classes.join(" ")
  end

  def scope_class(scope)
    "scope scope-#{scope.split(":").last}"
  end
end
