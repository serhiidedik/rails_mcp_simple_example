# Base class of every MCP tool. A tool is a thin adapter: it declares its contract (schemas,
# annotations, required scope) and hands the work to an interaction. This class enforces the
# scope, translates outcomes into MCP results and writes the audit log.
#
#   class Posts::GetTool < ApplicationTool
#     tool_name "get_post"
#     required_scope "posts:read"
#     input_schema(...)
#
#     def self.perform(id:)
#       respond_with(Posts::Find.run(id:)) { |post| Posts::ToolPayload.post(post) }
#     end
#   end
class ApplicationTool < MCP::Tool
  class << self
    # The OAuth scope a token needs to call this tool. McpEndpoint reads it to answer with
    # an HTTP 403 step-up challenge; #call enforces it again, so no path can skip the check.
    def required_scope(scope = nil)
      return @required_scope || raise(NotImplementedError, "#{name} must declare a required_scope") if scope.nil?

      @required_scope = scope
    end

    def call(server_context:, **arguments)
      server_context.require_scopes!(required_scope)

      audited(server_context) { perform_handling_failures(**arguments) }
    end

    private

    def perform(**)
      raise NotImplementedError, "#{name} must implement .perform"
    end

    # Expected failures become tool results with isError, which the model can read and act on.
    # Anything unexpected propagates: the SDK reports it and answers with a generic error,
    # so internals never reach the client.
    def perform_handling_failures(**arguments)
      perform(**arguments)
    rescue ActiveRecord::RecordNotFound => error
      error_response("#{error.model || "Record"} not found")
    end

    def respond_with(outcome)
      return error_response(outcome.errors.full_messages.to_sentence) unless outcome.valid?

      payload = yield(outcome.result)
      # The text copy is for clients that do not read structured content yet (MCP tools spec).
      MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], structured_content: payload)
    end

    def error_response(message)
      MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
    end

    # Who did what, with which client. Arguments are left out: they can hold user content.
    def audited(server_context)
      auth = server_context.auth_info
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = "exception"
      yield.tap { |response| result = response.error? ? "error" : "ok" }
    ensure
      Rails.logger.info(
        "mcp.tool_call tool=#{tool_name} result=#{result} user=#{auth&.subject} client=#{auth&.client_id.inspect} " \
        "duration_ms=#{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round}"
      )
    end
  end
end
