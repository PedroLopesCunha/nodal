class SettingPolicy < ApplicationPolicy
  # Only admin or owner can edit organisation settings
  def update?
    admin_or_owner_working_for_organisation?
  end

  private

  def admin_or_owner_working_for_organisation?
    return false unless member_working_for_organisation?

    org_member = OrgMember.find_by(member: user, organisation: record)
    org_member&.role.in?(%w[admin owner])
  end
end
