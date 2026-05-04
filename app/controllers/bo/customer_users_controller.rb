class Bo::CustomerUsersController < Bo::BaseController
  before_action :set_customer
  before_action :set_customer_user, only: [:edit, :update, :resend_invitation, :toggle_active]

  def new
    @customer_user = @customer.customer_users.build
    authorize @customer_user
  end

  def create
    @customer_user = @customer.customer_users.build(customer_user_params)
    @customer_user.organisation = @customer.organisation
    authorize @customer_user

    # Devise Invitable creates the record AND sends the invitation in one
    # call. We set invited_by polymorphically on the attrs hash (instead of
    # passing it as the second arg) because devise_invitable expects the
    # inviter to itself be Invitable, which Member is not — passing it as
    # the second arg would call decrement_invitation_limit! on Member.
    invite_attrs = customer_user_params.to_h.merge(
      customer_id: @customer.id,
      organisation_id: @customer.organisation_id,
      invited_by: current_member
    )
    @customer_user = CustomerUser.invite!(invite_attrs)

    if @customer_user.errors.empty?
      redirect_to bo_customer_path(params[:org_slug], @customer),
                  notice: t("bo.customer_users.flash.invited", email: @customer_user.email)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @customer_user
  end

  def update
    authorize @customer_user
    if @customer_user.update(customer_user_update_params)
      redirect_to bo_customer_path(params[:org_slug], @customer),
                  notice: t("bo.customer_users.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def resend_invitation
    authorize @customer_user
    @customer_user.invited_by = current_member
    @customer_user.invite!
    redirect_to bo_customer_path(params[:org_slug], @customer),
                notice: t("bo.customer_users.flash.invitation_resent", email: @customer_user.email)
  end

  def toggle_active
    authorize @customer_user
    @customer_user.update(active: !@customer_user.active?)
    key = @customer_user.active? ? "activated" : "deactivated"
    redirect_to bo_customer_path(params[:org_slug], @customer),
                notice: t("bo.customer_users.flash.#{key}", email: @customer_user.email)
  end

  private

  def set_customer
    @customer = current_organisation.customers.find(params[:customer_id])
  end

  def set_customer_user
    @customer_user = @customer.customer_users.find(params[:id])
  end

  # Email is set on creation only — changing it would invalidate Devise
  # auth tokens and any pending invite/reset links.
  def customer_user_params
    params.require(:customer_user).permit(
      :email, :contact_name, :contact_phone, :locale,
      :hide_prices, :email_notifications_enabled
    )
  end

  def customer_user_update_params
    params.require(:customer_user).permit(
      :contact_name, :contact_phone, :locale,
      :hide_prices, :email_notifications_enabled, :active
    )
  end
end
