module Posts
  class GetTool < ApplicationTool
    tool_name "get_post"
    title "Get post"
    description "Returns one post by id."
    required_scope "posts:read"
    annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: { id: { type: "integer", minimum: 1 } },
      required: %w[ id ],
      additionalProperties: false
    )
    output_schema(ToolPayload::POST)

    def self.perform(id:)
      respond_with(Find.run(id:)) { |post| ToolPayload.post(post) }
    end
  end
end
