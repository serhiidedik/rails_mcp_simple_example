module Posts
  class CreateTool < ApplicationTool
    tool_name "create_post"
    title "Create post"
    description "Creates a post. It stays unpublished unless published is true."
    required_scope "posts:write"
    annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false)
    input_schema(
      properties: {
        title: { type: "string", minLength: 1, maxLength: Post::TITLE_MAX_LENGTH },
        body: { type: "string", maxLength: Post::BODY_MAX_LENGTH },
        published: { type: "boolean", default: false }
      },
      required: %w[ title ],
      additionalProperties: false
    )
    output_schema(ToolPayload::POST)
    example arguments: { title: "Hello", body: "The first post" }, result: ToolPayload::EXAMPLE

    def self.perform(actor:, **arguments)
      respond_with(Create.run(arguments.merge(user_id: actor.user_id))) { |post| ToolPayload.post(post, actor) }
    end
  end
end
