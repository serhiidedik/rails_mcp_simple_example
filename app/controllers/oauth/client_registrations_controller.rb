module Oauth
  # POST /oauth/register: Dynamic Client Registration (RFC 7591).
  class ClientRegistrationsController < ActionController::API
    before_action { response.headers["Cache-Control"] = "no-store" }

    def create
      outcome = RegisterClient.run(params.permit(:client_name, redirect_uris: []).to_h)

      if outcome.valid?
        render json: registration_response(outcome.result), status: :created
      else
        render json: registration_error(outcome.errors), status: :bad_request
      end
    end

    private

    # Whatever auth method was requested, the client is public. RFC 7591 section 3.2.1 lets
    # the server substitute a value, as long as the response states what actually applies.
    def registration_response(application)
      {
        client_id: application.uid,
        client_id_issued_at: application.created_at.to_i,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split,
        grant_types: %w[ authorization_code refresh_token ],
        response_types: %w[ code ],
        token_endpoint_auth_method: "none",
        scope: Doorkeeper.config.scopes.to_s
      }
    end

    def registration_error(errors)
      {
        error: errors.include?(:redirect_uris) ? "invalid_redirect_uri" : "invalid_client_metadata",
        error_description: errors.full_messages.to_sentence
      }
    end
  end
end
