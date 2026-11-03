require "test_helper"

class Oauth::ResolveMetadataDocumentClientTest < ActiveSupport::TestCase
  Subject = Oauth::ResolveMetadataDocumentClient
  Fetcher = Oauth::FetchClientMetadataDocument
  URL = "https://app.example.com/oauth/client.json".freeze

  def serving(body)
    stub_instance_method(Fetcher, :resolve, ->(_hostname) { [ "93.184.216.34" ] }) do
      stub_instance_method(Fetcher, :read_body, ->(_uri, _address) { body.respond_to?(:call) ? body.call : body }) do
        yield
      end
    end
  end

  def document(redirect_uri: "https://app.example.com/cb", name: "App")
    { client_id: URL, client_name: name, redirect_uris: [ redirect_uri ] }.to_json
  end

  test "applies only to URL-shaped client ids" do
    assert Subject.applies_to?(URL)
    assert_not Subject.applies_to?("Ab3dE")
    assert_not Subject.applies_to?(nil)
    assert_not Subject.applies_to?("http://app.example.com/client.json")
  end

  test "creates a public client from the document" do
    application = serving(document) { Subject.run!(client_id: URL) }

    assert_equal URL, application.uid
    assert_equal "App", application.name
    assert_equal "https://app.example.com/cb", application.redirect_uri
    assert_equal false, application.confidential
    assert_equal "metadata_document", application.registration_type
  end

  test "serves the cached copy within the TTL" do
    serving(document) { Subject.run!(client_id: URL) }

    serving(-> { flunk "must not fetch again" }) { assert Subject.run(client_id: URL).valid? }
  end

  test "re-reads the document after the TTL, picking up changes" do
    serving(document) { Subject.run!(client_id: URL) }

    travel Subject::CACHE_TTL + 1.minute do
      application = serving(document(redirect_uri: "https://app.example.com/new", name: "Renamed")) { Subject.run!(client_id: URL) }

      assert_equal "https://app.example.com/new", application.redirect_uri
      assert_equal "Renamed", application.name
    end

    assert_no_difference("Doorkeeper::Application.count") { serving(document) { Subject.run(client_id: URL) } }
  end

  test "extends the cache when the document has not changed" do
    serving(document) { Subject.run!(client_id: URL) }

    travel Subject::CACHE_TTL + 1.minute do
      serving(document) { Subject.run!(client_id: URL) }

      serving(-> { flunk "must not fetch again" }) { assert Subject.run(client_id: URL).valid? }
    end
  end

  test "fails closed when a stale document can no longer be read" do
    serving(document) { Subject.run!(client_id: URL) }

    travel Subject::CACHE_TTL + 1.minute do
      assert_not serving(-> { raise SocketError }) { Subject.run(client_id: URL) }.valid?
    end
  end

  test "creates nothing from an invalid document" do
    assert_no_difference("Doorkeeper::Application.count") do
      assert_not serving("nope") { Subject.run(client_id: URL) }.valid?
    end
  end

  test "a lost registration race resolves to the winner's record" do
    winner = create_public_client(registration_type: "metadata_document")
    winner.update!(uid: URL, updated_at: 2.hours.ago)

    stub_instance_method(Subject, :store, ->(*) { raise ActiveRecord::RecordNotUnique }) do
      assert_equal winner, serving(document) { Subject.run!(client_id: URL) }
    end
  end
end
