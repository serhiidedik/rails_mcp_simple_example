require "test_helper"

class Oauth::RedirectUriPolicyTest < ActiveSupport::TestCase
  test "allows https and http on a loopback host" do
    %w[
      https://app.example.com/callback
      http://localhost:1234/callback
      http://127.0.0.1:1234/callback
      http://[::1]:1234/callback
    ].each { |uri| assert Oauth::RedirectUriPolicy.allowed?(uri), uri }
  end

  test "refuses everything else" do
    [
      "http://app.example.com/callback",
      "http://localhost.evil.example/callback",
      "javascript:alert(1)",
      "cursor://anysphere.cursor/callback",
      "urn:ietf:wg:oauth:2.0:oob",
      "https://app.example.com/callback#fragment",
      "https://user:pass@app.example.com/callback",
      "/relative/callback",
      "not a uri",
      "",
      nil
    ].each { |uri| assert_not Oauth::RedirectUriPolicy.allowed?(uri), uri.inspect }
  end
end
