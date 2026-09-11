module ApplicationCable
  class Connection < ActionCable::Connection::Base
    attr_reader :viewer

    def connect
      @viewer = Contact.find_by(id: cookies[:viewer_id])
    end
  end
end
