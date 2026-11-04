module Comments
  class GetTool < ApplicationTool
    tool_name "get_comment"
    title "Get comment"
    description "Returns one comment by id."
    required_scope "comments:read"
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: { id: { type: "integer", minimum: 1 } },
      required: %w[ id ],
      additionalProperties: false
    )
    output_schema(ToolPayload::COMMENT)
    example arguments: { id: 1 }, result: ToolPayload::EXAMPLE

    def self.perform(id:)
      respond_with(Find.run(id:)) { |comment| ToolPayload.comment(comment) }
    end
  end
end
