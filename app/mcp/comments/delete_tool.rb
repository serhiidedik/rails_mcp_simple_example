module Comments
  class DeleteTool < ApplicationTool
    tool_name "delete_comment"
    title "Delete comment"
    description "Permanently deletes a comment. Only its owner can do this. It cannot be undone."
    required_scope "comments:delete"
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

    def self.perform(actor:, id:)
      respond_with(Destroy.run(id:, actor:)) { |comment| { id: comment.id, deleted: comment.destroyed? } }
    end
  end
end
