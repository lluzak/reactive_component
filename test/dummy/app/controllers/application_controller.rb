class ApplicationController < ActionController::Base
  helper_method :current_contact, :viewer, :viewer_id

  private

  # The mailbox being looked at. Everyone shares Alice's inbox here.
  def current_contact
    @current_contact ||= Contact.first
  end

  # Who is looking. The dummy app has no login, so `?as=<contact id>` stands in
  # for one. It rides the URL rather than a cookie so that two tabs in one
  # browser are two different people.
  def viewer_id
    params[:as].presence
  end

  def viewer
    @viewer ||= Contact.find_by(id: viewer_id)
  end

  # Keeps the viewer across links within the app, so only the first visit needs
  # to name one.
  def default_url_options
    viewer_id ? { as: viewer_id } : {}
  end
end
