# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  delegate :turbo_stream_from, to: :helpers
end
