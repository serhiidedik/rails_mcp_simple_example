# The contract of this server, read from the tool classes, the way a generated openapi.json
# documents a REST API. MCP has no static document format for this: a client learns the contract
# from the live tools/list. So everything here derives from what answers that call:
#
#   GET /                  the reference for people (DocsController)
#   GET /docs/tools.json   the tools/list result, for tooling
#   docs/mcp-tools.json    the same, committed, so that a contract change shows up in a diff
#
# Run bin/rails mcp:docs after changing a tool. test/integration/mcp_api_reference_test.rb fails
# when the committed file is stale, and calls every documented example against the real endpoint.
class McpApiReference
  TOOLS_FILE = Rails.root.join("docs/mcp-tools.json")

  Field = Data.define(:name, :type, :required, :notes)

  def self.write
    TOOLS_FILE.dirname.mkpath
    TOOLS_FILE.write(new.tools_json)
  end

  def tools_document
    { tools: tools.map(&:to_h) }
  end

  def tools_json
    "#{JSON.pretty_generate(tools_document)}\n"
  end

  def settings
    Rails.configuration.x.mcp
  end

  def endpoint_url
    "#{settings.public_url}#{settings.endpoint_path}"
  end

  def tools
    McpEndpoint::TOOLS
  end

  def scopes
    Doorkeeper.configuration.scopes.to_a
  end

  def scope_label(scope)
    I18n.t("doorkeeper.scopes.#{scope}")
  end

  def base_scope?(scope)
    settings.base_scopes.include?(scope)
  end

  def tools_with_scope(scope)
    tools.select { |tool| tool.required_scope == scope }
  end

  def protocol_versions
    MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS
  end

  def behavior(tool)
    annotations = tool.to_h.fetch(:annotations)
    effect = if annotations[:readOnlyHint] then "Read-only"
    elsif annotations[:destructiveHint] then "Destructive"
    else "Adds data"
    end

    annotations[:idempotentHint] ? "#{effect}, safe to retry" : effect
  end

  def arguments_of(tool)
    fields(JSON.parse(tool.to_h.fetch(:inputSchema).to_json))
  end

  def result_of(tool)
    fields(JSON.parse(tool.to_h.fetch(:outputSchema).to_json))
  end

  private

  # The properties of a schema as table rows, with nested array items flattened to posts[].id.
  def fields(schema, prefix = "")
    required = schema.fetch("required", [])

    schema.fetch("properties", {}).flat_map do |name, property|
      path = "#{prefix}#{name}"
      field = Field.new(name: path, type: Array(property["type"]).join(" or "), required: required.include?(name), notes: notes(property))
      [ field, *(property["items"] ? fields(property["items"], "#{path}[].") : []) ]
    end
  end

  def notes(property)
    [
      property["description"],
      range(property["minimum"], property["maximum"]),
      range(property["minLength"], property["maxLength"], unit: " characters"),
      property["format"]&.then { |format| "Format: #{format}." },
      property.key?("default") ? "Default: #{property["default"]}." : nil
    ].compact.join(" ")
  end

  def range(min, max, unit: "")
    return "From #{min} to #{max}#{unit}." if min && max
    return "At least #{min}#{unit}." if min

    "At most #{max}#{unit}." if max
  end
end
