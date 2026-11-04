# Base class of every MCP tool. A tool is a thin adapter: it declares its contract (schemas,
# annotations, required scope) and hands the work to an interaction. This class enforces the
# scope, translates outcomes into MCP results and writes the audit log.
#
#   class Posts::GetTool < ApplicationTool
#     tool_name "get_post"
#     required_scope "posts:read"
#     input_schema(...)
#     example arguments: { id: 1 }, result: { id: 1, title: "Hello" }
#
#     def self.perform(actor:, id:)
#       respond_with(Posts::Find.run(id:)) { |post| Posts::ToolPayload.post(post, actor) }
#     end
#   end
class ApplicationTool < MCP::Tool
  class << self
    # The OAuth scope a token needs to call this tool. McpEndpoint reads it to answer with
    # an HTTP 403 challenge; #call enforces it again, so no path can skip the check.
    def required_scope(scope = nil)
      return @required_scope || raise(NotImplementedError, "#{name} must declare a required_scope") if scope.nil?

      @required_scope = scope
    end

    # A sample call for the reference at GET /. Clients never receive it, and a test runs it
    # against the real endpoint, so it cannot go stale.
    def example(arguments: nil, result: nil)
      return @example || raise(NotImplementedError, "#{name} must declare an example") if arguments.nil?

      @example = { arguments:, result: }
    end

    def call(server_context:, **arguments)
      server_context.require_scopes!(required_scope)

      # Who is asking comes from the verified token, and overrides anything in the arguments.
      actor = Actor.new(user_id: Integer(server_context.auth_info.subject))

      audited(server_context) { perform_handling_failures(**arguments, actor:) }
    end

    private

    def perform(**)
      raise NotImplementedError, "#{name} must implement .perform"
    end

    # Expected failures become tool results with isError, which the model can read and act on.
    # Things change between two calls, so these are normal: another user can delete a post the
    # model just read. Anything unexpected propagates: the SDK reports it and answers with a
    # generic error, so internals never reach the client.
    def perform_handling_failures(**arguments)
      perform(**arguments)
    rescue ActiveRecord::RecordNotFound => error
      model = error.model || "Record"
      error_response(
        "not_found",
        "#{model} #{error.id} does not exist. It may have been deleted since you last read it.".squish,
        "Do not retry with this id. Call list_#{model.tableize} to see what exists now, or tell the user it is gone."
      )
    rescue OwnerOnly::NotOwner => error
      error_response(
        "not_owner",
        "#{error.message}. You can only change your own #{error.record.class.table_name}.",
        "Do not retry. Tell the user that only the owner can make this change."
      )
    end

    def respond_with(outcome)
      unless outcome.valid?
        return error_response(
          "validation_failed",
          outcome.errors.full_messages.to_sentence,
          "Correct the listed fields and call the tool again.",
          fields: outcome.errors.to_hash
        )
      end

      payload = yield(outcome.result)
      # The text copy is for clients that do not read structured content yet (MCP tools spec).
      MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], structured_content: payload)
    end

    # What went wrong, as a stable code, a sentence, and what to do about it.
    def error_response(code, message, next_step, **details)
      error = { code:, message:, next_step:, **details }
      MCP::Tool::Response.new([ { type: "text", text: { error: }.to_json } ], error: true)
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
