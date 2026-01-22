class Storefront::ContactsController < Storefront::BaseController
  skip_after_action :verify_authorized

  def show
    @organisation = current_organisation
  end
end
