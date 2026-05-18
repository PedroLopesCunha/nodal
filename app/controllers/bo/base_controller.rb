class Bo::BaseController < ApplicationController
  layout "bo"
  before_action :check_membership
  before_action :redirect_pure_rep_from_admin_only_pages
  before_action :set_sidebar_counts

  helper_method :pure_sales_rep?, :sales_rep_capability?

  # Controllers a pure rep should never see in the BO (catalog admin,
  # discount rules, team management, org settings, etc.). Action-level
  # exceptions (e.g. team_members self-edit) are handled in the method below.
  PURE_REP_DENIED_CONTROLLERS = %w[
    products categories product_attributes product_variants
    pricing customer_product_discounts product_discounts
    customer_discounts order_discounts promo_codes
    customer_categories
    settings erp_settings homepage_settings email_settings background_tasks
  ].freeze

  # A member whose only function is selling — role: member with the sales_rep
  # flag on. Used to scope UI and tighten strong params.
  def pure_sales_rep?
    current_org_member&.is_sales_rep? && current_org_member.role == "member"
  end

  # Anyone with the sales_rep flag, regardless of role. Owners/admins who are
  # also reps see carteira UI in addition to their normal org powers.
  def sales_rep_capability?
    !!current_org_member&.is_sales_rep?
  end

  private

  # done before every bo/ route - checks if member is part of current org
  # redirets to root if not
  def check_membership
    return if !current_member.nil? && current_member.organisations.exists?(current_organisation.id)
    flash[:alert]
    redirect_to(root_path)
  end

  # Sidebar already hides admin-only items for pure reps, but a curious rep
  # could URL-craft. This guard sends them back to their carteira with a flash.
  def redirect_pure_rep_from_admin_only_pages
    return unless pure_sales_rep?
    # Don't loop on the carteira itself, nor block the impersonation start/end.
    return if controller_name.in?(%w[carteira impersonations])

    deny =
      if PURE_REP_DENIED_CONTROLLERS.include?(controller_name)
        true
      elsif controller_name == "customers" && action_name == "index"
        # Top-level admin list is replaced by carteira for pure reps.
        true
      elsif controller_name == "team_members"
        # Allow only self-edit (and its update) on the rep's own OrgMember row.
        editing_own = action_name.in?(%w[edit update]) &&
                      params[:id].to_s == current_org_member&.id.to_s
        !editing_own
      else
        false
      end

    if deny
      redirect_to bo_sales_rep_carteira_path(org_slug: current_organisation.slug),
                  alert: "Esta página não está disponível para vendedores."
    end
  end

  def set_sidebar_counts
    @unreviewed_orders_count = current_organisation.orders.unreviewed.count
    @pending_erp_sync_count = current_organisation.customers.pending_erp_sync.count
    @unseen_tasks_count = current_organisation.background_tasks
      .where(member: current_member)
      .where(status: [:pending, :running])
      .or(current_organisation.background_tasks
        .where(member: current_member)
        .where(status: [:completed, :failed, :cancelled], viewed_at: nil))
      .count
  end
end
