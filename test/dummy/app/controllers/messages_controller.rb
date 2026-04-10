class MessagesController < ApplicationController
  before_action :set_message, only: [:show, :toggle_star, :toggle_read]

  def index
    @messages = current_contact.received_messages.inbox.includes(:sender, :recipient, :labels).newest_first
  end

  def show
    @message.mark_as_read!
    @messages = current_contact.received_messages.inbox.includes(:sender, :recipient, :labels).newest_first
  end

  def toggle_star
    @message.toggle_starred!
    head :no_content
  end

  def toggle_read
    if @message.read?
      @message.update!(read_at: nil)
    else
      @message.mark_as_read!
    end
    head :no_content
  end

  private

  def set_message
    @message = Message.find(params[:id])
  end

  def current_contact
    @current_contact ||= Contact.first
  end
  helper_method :current_contact
end
