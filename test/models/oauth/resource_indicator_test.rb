require "test_helper"

class Oauth::ResourceIndicatorTest < ActiveSupport::TestCase
  test "accepts the canonical URI, also with uppercase scheme and host" do
    assert Oauth::ResourceIndicator.canonical?("http://localhost:3000/mcp")
    assert Oauth::ResourceIndicator.canonical?("HTTP://LOCALHOST:3000/mcp")
  end

  test "refuses any other resource" do
    [
      "http://localhost:3000",
      "http://localhost:3000/mcp/",
      "http://localhost:3000/MCP",
      "http://localhost:3001/mcp",
      "https://localhost:3000/mcp",
      "https://evil.example/mcp",
      "not a uri",
      nil
    ].each { |uri| assert_not Oauth::ResourceIndicator.canonical?(uri), uri.inspect }
  end
end
