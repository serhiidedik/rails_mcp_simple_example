module Posts
  class UpdateTool < ApplicationTool
    tool_name "update_post"
    title "Update post"
    description "Changes the given fields of a post and leaves the others as they are."
    required_scope "posts:write"
    # Destructive: it overwrites existing content.
    annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        id: { type: "integer", minimum: 1 },
        title: { type: "string", minLength: 1, maxLength: Post::TITLE_MAX_LENGTH },
        body: { type: [ "string", "null" ], maxLength: Post::BODY_MAX_LENGTH },
        published: { type: "boolean" }
      },
      required: %w[ id ],
      additionalProperties: false
    )
    output_schema(ToolPayload::POST)

    def self.perform(**arguments)
      respond_with(Update.run(arguments)) { |post| ToolPayload.post(post) }
    end
  end
end
