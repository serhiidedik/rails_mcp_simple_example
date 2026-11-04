module Posts
  # What the tools return for a post: the output schema and the serializer that must match it.
  # The SDK validates each result against the schema, so they cannot drift apart unnoticed.
  module ToolPayload
    POST = {
      type: "object",
      properties: {
        id: { type: "integer" },
        user_id: { type: "integer", description: "The owner." },
        mine: { type: "boolean", description: "True when you own this, and so can change it." },
        title: { type: "string" },
        body: { type: [ "string", "null" ] },
        published: { type: "boolean" },
        created_at: { type: "string", format: "date-time" },
        updated_at: { type: "string", format: "date-time" }
      },
      required: %w[ id user_id mine title body published created_at updated_at ],
      additionalProperties: false
    }.freeze

    EXAMPLE = {
      id: 1,
      user_id: 1,
      mine: true,
      title: "Hello",
      body: "The first post",
      published: false,
      created_at: "2026-11-04T10:00:00Z",
      updated_at: "2026-11-04T10:00:00Z"
    }.freeze

    module_function

    def post(post, actor)
      {
        id: post.id,
        user_id: post.user_id,
        mine: actor.owns?(post),
        title: post.title,
        body: post.body,
        published: post.published?,
        created_at: post.created_at.iso8601,
        updated_at: post.updated_at.iso8601
      }
    end
  end
end
