module Oauth
  # Turns a URL-shaped client_id into a Doorkeeper application, so the rest of the
  # authorization flow treats it like any other client. The document is the source of truth:
  # it is re-read when the cached copy is older than CACHE_TTL, and a document that has become
  # invalid or unreachable stops the flow instead of falling back to the stale copy.
  class ResolveMetadataDocumentClient < ApplicationInteraction
    CACHE_TTL = 1.hour
    REGISTRATION_TYPE = "metadata_document"

    string :client_id, strip: false

    def self.applies_to?(client_id)
      client_id.to_s.start_with?("https://")
    end

    def execute
      application = Doorkeeper::Application.find_or_initialize_by(uid: client_id)
      return application if application.persisted? && application.updated_at > CACHE_TTL.ago

      store(application, compose(FetchClientMetadataDocument, url: client_id))
    rescue ActiveRecord::RecordNotUnique
      # A concurrent first request registered the same client: its fresh copy is as good.
      Doorkeeper::Application.find_by!(uid: client_id)
    end

    private

    def store(application, document)
      application.assign_attributes(
        name: document[:client_name],
        redirect_uri: document[:redirect_uris].join("\n"),
        confidential: false,
        registration_type: REGISTRATION_TYPE,
        updated_at: Time.current
      )
      errors.merge!(application.errors) unless application.save
      application
    end
  end
end
