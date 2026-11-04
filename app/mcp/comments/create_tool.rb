module Comments
  class CreateTool < ApplicationTool
    tool_name "create_comment"
    title "Create comment"
    description "Adds a comment to any post. You own the comment."
    required_scope "comments:write"
    annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false)
    input_schema(
      properties: {
        post_id: { type: "integer", minimum: 1 },
        body: { type: "string", minLength: 1, maxLength: Comment::BODY_MAX_LENGTH }
      },
      required: %w[ post_id body ],
      additionalProperties: false
    )
    output_schema(ToolPayload::COMMENT)
    example arguments: { post_id: 1, body: "Nice post" }, result: ToolPayload::EXAMPLE

    def self.perform(actor:, **arguments)
      respond_with(Create.run(arguments.merge(user_id: actor.user_id))) { |comment| ToolPayload.comment(comment, actor) }
    end
  end
end
