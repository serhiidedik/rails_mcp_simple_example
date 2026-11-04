module Comments
  class ListTool < ApplicationTool
    tool_name "list_comments"
    title "List comments"
    description "Lists the comments of a post, newest first. Pass next_cursor back as cursor to get the following page."
    required_scope "comments:read"
    annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
    input_schema(
      properties: {
        post_id: { type: "integer", minimum: 1 },
        cursor: { type: "string", description: "The next_cursor of the previous page. Omit it for the first page." },
        limit: { type: "integer", minimum: 1, maximum: List::MAX_LIMIT, default: List::DEFAULT_LIMIT }
      },
      required: %w[ post_id ],
      additionalProperties: false
    )
    output_schema(
      properties: {
        comments: { type: "array", items: ToolPayload::COMMENT },
        next_cursor: { type: [ "string", "null" ], description: "Null on the last page." }
      },
      required: %w[ comments next_cursor ],
      additionalProperties: false
    )
    example arguments: { post_id: 1, limit: 1 }, result: { comments: [ ToolPayload::EXAMPLE.merge(id: 2) ], next_cursor: "Mg" }

    def self.perform(**arguments)
      respond_with(List.run(arguments)) do |page|
        { comments: page.records.map { |comment| ToolPayload.comment(comment) }, next_cursor: page.next_cursor }
      end
    end
  end
end
