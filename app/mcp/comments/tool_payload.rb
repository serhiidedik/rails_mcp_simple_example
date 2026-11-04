module Comments
  # What the tools return for a comment: the output schema and the serializer that must match it.
  # The SDK validates each result against the schema, so they cannot drift apart unnoticed.
  module ToolPayload
    COMMENT = {
      type: "object",
      properties: {
        id: { type: "integer" },
        post_id: { type: "integer" },
        body: { type: "string" },
        created_at: { type: "string", format: "date-time" },
        updated_at: { type: "string", format: "date-time" }
      },
      required: %w[ id post_id body created_at updated_at ],
      additionalProperties: false
    }.freeze

    EXAMPLE = {
      id: 1,
      post_id: 1,
      body: "Nice post",
      created_at: "2026-11-04T10:00:00Z",
      updated_at: "2026-11-04T10:00:00Z"
    }.freeze

    module_function

    def comment(comment)
      {
        id: comment.id,
        post_id: comment.post_id,
        body: comment.body,
        created_at: comment.created_at.iso8601,
        updated_at: comment.updated_at.iso8601
      }
    end
  end
end
