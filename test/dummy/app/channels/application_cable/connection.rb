module ApplicationCable
  class Connection < ActionCable::Connection::Base
    attr_reader :viewer

    # Who is looking, taken from the socket's own query string rather than a
    # cookie. A cookie is shared by every tab in a browser, which made two tabs
    # the same person and each one filter the other out of its roster.
    def connect
      @viewer = Contact.find_by(id: request.params[:as])
    end
  end
end
