class CustomerUsers::PasswordsController < Devise::PasswordsController
  before_action :set_organisation

  def after_resetting_password_path_for(_resource)
    home_path(org_slug: @organisation.slug)
  end

  private

  def set_organisation
    @organisation = Organisation.find_by!(slug: params[:org_slug])
  end
end
