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

  private

  def toggle_read
    if @message.read?
      @message.update!(read_at: nil)
    else
      @message.mark_as_read!
    end
  end

  def move(label:)
    @message.update!(label: label)
    Turbo::StreamsChannel.broadcast_remove_to(
      [@message.recipient, :messages],
      target: ActionView::RecordIdentifier.dom_id(@message)
    )
  end
end
