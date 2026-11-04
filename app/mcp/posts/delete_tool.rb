module Posts
  class DeleteTool < ApplicationTool
    tool_name "delete_post"
    title "Delete post"
    description "Permanently deletes a post and its comments. This cannot be undone."
    required_scope "posts:delete"
    annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: { id: { type: "integer", minimum: 1 } },
      required: %w[ id ],
      additionalProperties: false
    )
    output_schema(
      properties: { id: { type: "integer" }, deleted: { type: "boolean" } },
      required: %w[ id deleted ],
      additionalProperties: false
    )
    example arguments: { id: 1 }, result: { id: 1, deleted: true }

    def self.perform(id:)
      respond_with(Destroy.run(id:)) { |post| { id: post.id, deleted: post.destroyed? } }
    end
  end
end
