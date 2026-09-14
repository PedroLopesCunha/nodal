class Bo::BulkInvitationsController < Bo::BaseController
  include RepFilterOptions

  # The picker's list, loaded into the modal's turbo frame and reloaded
  # whenever a filter changes.
  def new
    authorize Customer, :bulk_invite?

    @candidates = CustomerInvitations::Finder.new(
      organisation: current_organisation,
      status: params[:status],
      sent_from: params[:sent_from],
      sent_to: params[:sent_to],
      rep: params[:rep],
      query: params[:query]
    ).candidates

    render partial: "picker", formats: [:html]
  end

  def create
    authorize Customer, :bulk_invite?

    customer_ids = current_organisation.customers.where(id: Array(params[:customer_ids])).pluck(:id)
    if customer_ids.empty?
      redirect_to bo_customers_path(params[:org_slug]), alert: t("bo.bulk_invitations.flash.none_selected")
      return
    end

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "bulk_customer_invitation",
      status: :pending
    )
    BulkInvitationJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      member_id: current_member.id,
      customer_ids: customer_ids
    )

    redirect_to bo_background_task_path(params[:org_slug], task)
  end
end
