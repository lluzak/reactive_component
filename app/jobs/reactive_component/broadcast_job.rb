# frozen_string_literal: true

module ReactiveComponent
  # Carries a broadcast out of the request that committed the record. The
  # request id travels with it so a client can still skip its own broadcast.
  # A record deleted before the job runs has nothing left to render, so the
  # job is dropped rather than retried.
  class BroadcastJob < ActiveJob::Base
    discard_on ActiveJob::DeserializationError

    def perform(component_class_name, record, action, request_id = nil)
      Turbo.with_request_id(request_id) do
        ReactiveComponent.broadcast_for(component_class_name.constantize, record, action: action.to_sym)
      end
    end
  end
end
