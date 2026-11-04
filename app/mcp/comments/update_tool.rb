module Comments
  class UpdateTool < ApplicationTool
    tool_name "update_comment"
    title "Update comment"
    description "Replaces the body of a comment. A comment stays on its post. Only its owner can do this."
    required_scope "comments:write"
    # Destructive: it overwrites existing content.
    annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        id: { type: "integer", minimum: 1 },
        body: { type: "string", minLength: 1, maxLength: Comment::BODY_MAX_LENGTH }
      },
      required: %w[ id body ],
      additionalProperties: false
    )
    output_schema(ToolPayload::COMMENT)
    example arguments: { id: 1, body: "Edited" },
            result: ToolPayload::EXAMPLE.merge(body: "Edited", updated_at: "2026-11-04T10:05:00Z")

    def self.perform(actor:, **arguments)
      respond_with(Update.run(arguments.merge(actor:))) { |comment| ToolPayload.comment(comment, actor) }
    end
  end
end
