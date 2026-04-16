class MessagesController < ApplicationController
  FOLDERS = {
    "inbox" => { label: "Inbox", icon: "inbox", scope: ->(contact) { contact.received_messages.inbox } },
    "starred" => { label: "Starred", icon: "star", scope: ->(contact) { contact.received_messages.starred_messages } },
    "sent" => { label: "Sent", icon: "paper-airplane", scope: ->(contact) { contact.sent_messages } },
    "archive" => { label: "Archive", icon: "archive-box", scope: ->(contact) { contact.received_messages.archived } },
    "trash" => { label: "Trash", icon: "trash", scope: ->(contact) { contact.received_messages.trashed } }
  }.freeze

  before_action :set_message, only: [:show, :toggle_star, :toggle_read]
  before_action :set_folder

  def index
    @messages = folder_messages
  end

  def show
    @message.mark_as_read!
    @messages = folder_messages
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

  def set_folder
    @folder = FOLDERS.key?(params[:folder]) ? params[:folder] : "inbox"
    @folder_config = FOLDERS[@folder]
  end

  def folder_messages
    @folder_config[:scope].call(current_contact).includes(:sender, :recipient, :labels).newest_first
  end

  def current_contact
    @current_contact ||= Contact.first
  end
  helper_method :current_contact
end
