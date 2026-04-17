# frozen_string_literal: true

# Regression fixture mirroring a real-world ticket/row component. Exercises
# every pattern that has historically broken the compiler:
#
#   - outer `<%= tag.div ... do %>` block with dynamic id/class/data attrs
#   - inner `<%= tag.div ... do %>` for a conditional banner
#   - `<%= raw bare_helper %>` (server-computed HTML, no ivar in arg)
#   - `<%= raw @ivar_html %>` (server-computed HTML with ivar)
#   - `render SubComponent.new(...)` inside a collection loop
#   - `render WrapperComponent.new(**opts)` whose template splats `**@options`
#   - i18n helper calls, time-ago helpers, method calls on ivar chains
#
# If you're reading this because the compiler blew up on a real template,
# add a line to this fixture that reproduces the shape, then fix the
# compiler until this test passes again.
class RichRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message, class_name: "Message"
  broadcasts stream: ->(message) { [message.recipient, :rich_rows] }

  def initialize(message:, active: false)
    @message = message
    @active = active
  end

  private

  def row_classes
    ["rich-row", {"rich-row--active": @active}, "rich-row--#{@message.read? ? "read" : "unread"}"]
  end

  def status_badge_html
    %(<span class="status-badge">#{@message.read? ? "Read" : "New"}</span>).html_safe
  end

  def sparkle_icon_svg
    %(<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="3"/></svg>).html_safe
  end

  def banner_visible?
    @message.starred? && !@message.read?
  end

  def ago
    time_ago_in_words(@message.created_at)
  end
end
