class ApplicationController < ActionController::Base
  helper_method :current_contact, :viewer, :viewer_id

  # Nobody arrives with `?as=` on their own, and an unnamed viewer gets no
  # presence at all, which looks exactly like presence being broken. Name one.
  before_action :ensure_viewer


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

  def ensure_viewer
    return if viewer_id.present? || !request.get? || request.xhr?

    redirect_to url_for(params.permit!.merge(as: Contact.order(:id).first&.id))
  end
end
