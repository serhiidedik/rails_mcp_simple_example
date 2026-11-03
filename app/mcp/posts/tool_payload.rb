module Posts
  # What the tools return for a post: the output schema and the serializer that must match it.
  # The SDK validates each result against the schema, so they cannot drift apart unnoticed.
  module ToolPayload
    POST = {
      type: "object",
      properties: {
        id: { type: "integer" },
        title: { type: "string" },
        body: { type: [ "string", "null" ] },
        published: { type: "boolean" },
        created_at: { type: "string", format: "date-time" },
        updated_at: { type: "string", format: "date-time" }
      },
      required: %w[ id title body published created_at updated_at ],
      additionalProperties: false
    }.freeze

    module_function

    def post(post)
      {
        id: post.id,
        title: post.title,
        body: post.body,
        published: post.published?,
        created_at: post.created_at.iso8601,
        updated_at: post.updated_at.iso8601
      }
    end
  end
end
