# frozen_string_literal: true

class BoardCardComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }
  live_action :move, params: [:label]

  def self.dom_id_prefix = :card

  def initialize(message:)
    @message = message
  end

  private

  def move(label:)
    @message.update!(label: label) if Message::LABELS.include?(label)
  end
end
