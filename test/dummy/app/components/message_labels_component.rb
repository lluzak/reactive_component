# frozen_string_literal: true

class MessageLabelsComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }

  def self.dom_id_prefix = :labels

  live_action :add_label, params: [:label_id]
  live_action :remove_label, params: [:label_id]

  def initialize(message:)
    @message = message
    @labels = Label.order(:name)
  end
end
