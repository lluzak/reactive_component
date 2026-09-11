class ApplicationController < ActionController::Base
  helper_method :current_contact, :viewer_id

  private

  # The mailbox being looked at. Everyone shares Alice's inbox here.
  def current_contact
    @current_contact ||= Contact.first
  end

  # Who is looking. The dummy app has no login, so `?as=<contact id>` stands in
  # for one. It rides the URL, not a cookie, so two tabs can be two people.
  def viewer_id
    params[:as].presence
  end
end
