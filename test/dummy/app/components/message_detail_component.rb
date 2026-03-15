# frozen_string_literal: true

class MessageDetailComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }

  def self.dom_id_prefix = :detail

  live_action :toggle_read
  live_action :move, params: [:label]

  def initialize(message:)
    @message = message
  end
end
