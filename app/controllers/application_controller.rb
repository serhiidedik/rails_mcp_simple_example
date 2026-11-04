class ApplicationController < ActionController::API
  rescue_from ActiveInteraction::InvalidInteractionError do |error|
    render json: error.interaction.errors, status: :unprocessable_content
  end
end
