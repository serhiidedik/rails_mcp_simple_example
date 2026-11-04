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
      params[:scope] = every_scope if known_scopes_requested?
    end

    # One consent covers every tool, whatever the client asks for: clients can remember the scopes
    # of an earlier sign-in and ask for those again. The page lists what is granted, and the token
    # response reports it (RFC 6749, section 3.3). An unknown scope stays, so that it is refused.
    def known_scopes_requested?
      Doorkeeper::OAuth::Scopes.from_string(params[:scope].to_s).all? { |scope| Doorkeeper.config.scopes.exists?(scope) }
    end

    def every_scope
      Doorkeeper.config.scopes.to_s
    end

    def resolve_metadata_document_client
      client_id = params[:client_id]
      return unless ResolveMetadataDocumentClient.applies_to?(client_id)
      return if ResolveMetadataDocumentClient.run(client_id: client_id.to_s).valid?

      render_error_response(Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_client))
    end
  end
end
