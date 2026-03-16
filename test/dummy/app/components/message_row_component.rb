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

  LABEL_COLORS = {
    "blue" => "bg-blue-100 text-blue-700",
    "red" => "bg-red-100 text-red-700",
    "green" => "bg-green-100 text-green-700",
    "yellow" => "bg-yellow-100 text-yellow-700",
    "purple" => "bg-purple-100 text-purple-700",
    "pink" => "bg-pink-100 text-pink-700",
    "indigo" => "bg-indigo-100 text-indigo-700",
    "gray" => "bg-gray-100 text-gray-700"
  }.freeze

  def label_color_classes(label)
    LABEL_COLORS.fetch(label.color, LABEL_COLORS["blue"])
  end
end
