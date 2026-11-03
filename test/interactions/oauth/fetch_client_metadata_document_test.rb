require "test_helper"

class Oauth::FetchClientMetadataDocumentTest < ActiveSupport::TestCase
  Subject = Oauth::FetchClientMetadataDocument
  URL = "https://app.example.com/oauth/client.json".freeze

  def document(**overrides)
    { client_id: URL, client_name: "App", redirect_uris: [ "https://app.example.com/cb" ] }.merge(overrides).compact.to_json
  end

  # Network stubbed at the seams: a public address and a canned body.
  def fetch(body: document, addresses: [ "93.184.216.34" ], url: URL)
    stub_instance_method(Subject, :resolve, ->(_hostname) { addresses }) do
      stub_instance_method(Subject, :read_body, ->(_uri, _address) { body.respond_to?(:call) ? body.call : body }) do
        Subject.run(url:)
      end
    end
  end

  test "returns the validated fields of a good document" do
    outcome = fetch

    assert outcome.valid?
    assert_equal({ client_name: "App", redirect_uris: [ "https://app.example.com/cb" ] }, outcome.result)
  end

  test "refuses URLs outside the client id rules without any network access" do
    no_network = ->(*) { flunk "must not touch the network" }

    stub_instance_method(Subject, :resolve, no_network) do
      [
        "http://app.example.com/client.json",
        "https://app.example.com:8443/client.json",
        "https://user:pass@app.example.com/client.json",
        "https://app.example.com/client.json?x=1",
        "https://app.example.com/client.json#x",
        "https://app.example.com",
        "https://app.example.com/",
        "https://app.example.com/a/../client.json",
        "https://app.example.com/./client.json",
        "https://app.example.com/#{"x" * 2100}",
        "https://exa mple.com/client.json"
      ].each { |url| assert_not Subject.run(url:).valid?, url }
    end
  end

  test "refuses a host resolving to a non-public address" do
    [
      "127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1",
      "0.0.0.0", "::1", "::", "fc00::1", "fe80::1", "::ffff:10.0.0.1", "::ffff:169.254.169.254"
    ].each do |address|
      outcome = fetch(addresses: [ address ], body: -> { flunk "must not connect to #{address}" })

      assert_not outcome.valid?, address
    end
  end

  test "refuses a host with any non-public address among public ones" do
    assert_not fetch(addresses: [ "93.184.216.34", "10.0.0.1" ]).valid?
  end

  test "refuses a host that does not resolve" do
    assert_not fetch(addresses: []).valid?
  end

  test "refuses a document that does not hold up" do
    [
      document(client_id: "https://other.example/client.json"),
      document(client_id: nil),
      document(client_name: nil),
      document(client_name: ""),
      document(client_name: "x" * 201),
      document(client_name: { a: 1 }),
      document(redirect_uris: []),
      document(redirect_uris: "https://app.example.com/cb"),
      document(redirect_uris: [ "http://app.example.com/cb" ]),
      document(redirect_uris: [ 1 ]),
      document(token_endpoint_auth_method: "private_key_jwt"),
      document(client_secret: "s3cret"),
      "[1, 2]",
      "not json",
      ""
    ].each { |body| assert_not fetch(body:).valid?, body }
  end

  test "reports network failures without details" do
    [ SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, OpenSSL::SSL::SSLError ].each do |error|
      outcome = fetch(body: -> { raise error, "internal.host:5432 said no" })

      assert_not outcome.valid?
      assert_not_includes outcome.errors.full_messages.to_sentence, "internal.host"
    end
  end

  test "connects to the checked address and ignores proxy settings" do
    http = Subject.send(:new, url: URL).send(:build_http, URI.parse(URL), "93.184.216.34")

    assert_equal "93.184.216.34", http.ipaddr
    assert_equal "app.example.com", http.address
    assert_predicate http, :use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_not_predicate http, :proxy?
    assert_equal Subject::TIMEOUT_SECONDS, http.read_timeout
  end

  # The HTTP handling, against a real socket.
  test "does not follow redirects" do
    assert_not fetch_from_server("HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/\r\nContent-Length: 0\r\n\r\n").valid?
  end

  test "refuses a non-200 response" do
    assert_not fetch_from_server("HTTP/1.1 500 Oops\r\nContent-Length: 0\r\n\r\n").valid?
  end

  test "stops reading a body over the size limit" do
    body = document(client_name: "x" * Subject::MAX_BODY_BYTES)

    assert_not fetch_from_server("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}").valid?
  end

  test "reads a good response" do
    body = document

    assert fetch_from_server("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}").valid?
  end

  private

  def fetch_from_server(raw_response)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      socket = server.accept
      while (line = socket.gets) && line != "\r\n"; end
      socket.write(raw_response)
      socket.close
    rescue IOError, SystemCallError
      nil
    end

    stub_instance_method(Subject, :public_address_of, ->(_hostname) { "127.0.0.1" }) do
      stub_instance_method(Subject, :build_http, ->(_uri, _address) { Net::HTTP.new("127.0.0.1", port, nil) }) do
        Subject.run(url: URL)
      end
    end
  ensure
    thread&.kill
    server&.close
  end
end
