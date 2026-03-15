# frozen_string_literal: true

class MessageRowComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] },
             prepend_target: "message_items"
  live_action :toggle_star
  client_state :selected, default: false

  def initialize(message:, selected: false)
    @message = message
    @selected = selected
  end

  private

  def toggle_star
    @message.toggle_starred!
  end

  def avatar_color(sender)
    sender.avatar_color
  end
end
