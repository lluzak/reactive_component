# frozen_string_literal: true

module ReactiveComponent
  class ActionsController < ActionController::Base
    def create
      payload = verify_token!.symbolize_keys
      component_class = payload[:c].constantize
      record = payload[:m].constantize.find(payload[:r])

      component_class.execute_action(
        params[:action_name],
        record,
        params.fetch(:params, {}).permit!.to_h
      )

      head :ok
    end

    private

    def verify_token!
      Rails.application.message_verifier(:reactive_component_action)
           .verify(params[:token], purpose: :reactive_component_action)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ActionController::RoutingError, 'Not found'
    end
  end
end
