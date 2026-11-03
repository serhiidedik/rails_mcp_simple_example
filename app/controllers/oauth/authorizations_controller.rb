module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    # Prepended: both must run before Doorkeeper validates the client.
    prepend_before_action :resolve_metadata_document_client, only: :new
    prepend_before_action :apply_request_defaults

    private

    def apply_request_defaults
      # MCP clients must send `resource`, older ones do not. This server protects exactly one
      # resource, so binding their token to it is safe, and no token ever lacks an audience.
      params[:resource] = ResourceIndicator.canonical if params[:resource].blank?
      # The only mode advertised in the metadata: the others need scripts that the CSP blocks.
      params.delete(:response_mode)
    end

    def resolve_metadata_document_client
      client_id = params[:client_id]
      return unless ResolveMetadataDocumentClient.applies_to?(client_id)
      return if ResolveMetadataDocumentClient.run(client_id: client_id.to_s).valid?

      render_error_response(Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_client))
    end
  end
end
