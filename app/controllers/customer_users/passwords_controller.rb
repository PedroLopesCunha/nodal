class CustomerUsers::PasswordsController < Devise::PasswordsController
  before_action :set_organisation

  def after_resetting_password_path_for(_resource)
    home_path(org_slug: @organisation.slug)
  end

  private

  # current_organisation resolves by request.host first (custom domain) and
  # falls back to params[:org_slug] so the reset flow works on either shape.
  def set_organisation
    @organisation = current_organisation || raise(ActiveRecord::RecordNotFound)
  end
end
