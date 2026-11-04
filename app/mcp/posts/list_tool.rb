module Posts
  class ListTool < ApplicationTool
    tool_name "list_posts"
    title "List posts"
    description "Lists posts, newest first. Pass next_cursor back as cursor to get the following page."
    required_scope "posts:read"
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        cursor: { type: "string", description: "The next_cursor of the previous page. Omit it for the first page." },
        limit: { type: "integer", minimum: 1, maximum: List::MAX_LIMIT, default: List::DEFAULT_LIMIT }
      },
      additionalProperties: false
    )
    output_schema(
      properties: {
        posts: { type: "array", items: ToolPayload::POST },
        next_cursor: { type: [ "string", "null" ], description: "Null on the last page." }
      },
      required: %w[ posts next_cursor ],
      additionalProperties: false
    )
    example arguments: { limit: 1 }, result: { posts: [ ToolPayload::EXAMPLE.merge(id: 2) ], next_cursor: "Mg" }

    def self.perform(**arguments)
      respond_with(List.run(arguments)) do |page|
        { posts: page.posts.map { |post| ToolPayload.post(post) }, next_cursor: page.next_cursor }
      end
    end
  end
end
