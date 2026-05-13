class Bo::BaseController < ApplicationController
  layout "bo"
  before_action :check_membership
  before_action :set_sidebar_counts

  helper_method :pure_sales_rep?, :sales_rep_capability?

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
