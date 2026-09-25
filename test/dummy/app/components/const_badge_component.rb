# frozen_string_literal: true

# Exercises `const(...)`: the badge never changes between renders, so it is
# baked into the compiled template rather than sent with every payload.
class ConstBadgeComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message

  def initialize(message:)
    @message = message
  end

  private

  def badge_icon = '<svg class="badge-icon"><use href="#star"></use></svg>'.html_safe
end
