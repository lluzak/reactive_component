class ApplicationController < ActionController::Base
  before_action :remember_viewer

  private

  # The mailbox being looked at. Everyone shares Alice's inbox here.
  def current_contact
    @current_contact ||= Contact.first
  end
  helper_method :current_contact

  # Who is looking. The dummy app has no login, so `?as=<contact id>` stands in
  # for one and lets a system test drive two browsers as two different people.
  def remember_viewer
    cookies[:viewer_id] = params[:as] if params[:as].present?
  end
end
