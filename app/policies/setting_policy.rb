class SettingPolicy < ApplicationPolicy
  # Only admin or owner can edit organisation settings
  def edit?
    admin_or_owner?
  end

  def update?
    admin_or_owner?
  end

  def email_logs?
    admin_or_owner?
  end

  # Deciding which companies see stock quantities is the same authority as
  # turning the setting on in the first place.
  def manage_stock_visibility?
    admin_or_owner?
  end

  private

  def admin_or_owner?
    return false unless user.is_a?(Member)

    org_member = OrgMember.find_by(member: user, organisation: record)
    org_member&.role.in?(%w[admin owner])
  end
end
