class CustomerUsers::SessionsController < Devise::SessionsController
  before_action :set_organisation
  before_action :configure_sign_in_params, only: :create

  def create
    customer_user = @organisation.customer_users.find_by(email: sign_in_params[:email])

    if customer_user&.valid_password?(sign_in_params[:password])
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, customer_user)
      yield customer_user if block_given?
      respond_with customer_user, location: after_sign_in_path_for(customer_user)
    else
      self.resource = resource_class.new(sign_in_params)
      set_flash_message!(:alert, :invalid)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_organisation
    @organisation = Organisation.find_by!(slug: params[:org_slug])
  end

  # Inject organisation_id so Devise authenticates on [email, organisation_id]
  def configure_sign_in_params
    params[:customer_user] ||= {}
    params[:customer_user][:organisation_id] = @organisation.id
    devise_parameter_sanitizer.permit(:sign_in, keys: [:organisation_id])
  end

  def after_sign_in_path_for(resource)
    home_path(org_slug: current_organisation.slug)
  end
end
