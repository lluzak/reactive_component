# frozen_string_literal: true

class BoardCardComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }
  live_action :move, params: [:label, :after]

  def self.dom_id_prefix = :card

  def initialize(message:)
    @message = message
  end

  private

  # An anchor, not an index: "after this card" survives two people reordering
  # the same column, where a fixed number would not.
  def move(label:, after: nil)
    return unless Message::LABELS.include?(label)

    @message.move_to!(label: label, after: after.presence)
  end
end
