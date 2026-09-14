module RepFilterOptions
  extend ActiveSupport::Concern

  private

  # [name, id] pairs for a "Vendedor" filter: current reps plus anyone who lost
  # the flag but still holds a carteira — otherwise those customers could no
  # longer be found by rep.
  def rep_filter_options
    members = current_organisation.org_members
    assigned_ids = CustomerAssignment.joins(:customer)
                                     .where(customers: { organisation_id: current_organisation.id })
                                     .select(:org_member_id)
    members.where(is_sales_rep: true).or(members.where(id: assigned_ids))
           .accepted.includes(:member)
           .sort_by { |om| om.display_name.to_s.squish.downcase }
           .map { |om| [om.display_name.to_s.squish, om.id.to_s] }
  end
end
