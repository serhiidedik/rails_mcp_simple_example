module Posts
  class ListTool < ApplicationTool
    tool_name "list_posts"
    title "List posts"
    description "Lists posts of every user, newest first. Pass mine to see only your own. Pass next_cursor back as cursor to get the following page."
    required_scope "posts:read"
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        mine: { type: "boolean", description: "True returns only your own posts." },
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

    def self.perform(actor:, mine: false, **arguments)
      arguments[:user_id] = actor.user_id if mine

      respond_with(List.run(arguments)) do |page|
        { posts: page.records.map { |post| ToolPayload.post(post, actor) }, next_cursor: page.next_cursor }
      end
    end
  end
end
