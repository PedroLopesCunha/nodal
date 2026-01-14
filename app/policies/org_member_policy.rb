class OrgMemberPolicy < ApplicationPolicy
  # Admin/Owner can invite new members
  def new?
    member_working_for_organisation? && admin_or_owner?
  end

  def create?
    member_working_for_organisation? && record_belongs_to_user_organisation? &&
      admin_or_owner?
  end

  # Only owner can edit roles
  def update?
    member_working_for_organisation? && record_belongs_to_user_organisation? &&
      owner? && !editing_self?
  end

  # Owner can remove anyone except themselves
  def destroy?
    owner? && !editing_self?
  end

  # Toggle active status
  def toggle_active?
    (owner? && !editing_self?) || (admin? && record.role == 'member')
    # Admins can toggle members but not other admins/owners
  end

  def resend_invitation?
    admin_or_owner? && record.pending_invitation?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless member_working_for_organisation?

      scope.where(organisation: @organisation)
    end
  end

  private

  def member_role
    user_is_a_member? ? user.org_members.find_by(organisation: @organisation).role : "no role"
  end

  def owner?
    member_role == 'owner'
  end

  def admin?
    member_role == 'admin'
  end

  def admin_or_owner?
    member_role.in?(%w[admin owner])
  end

  def editing_self?
    user.is_a?(Member) && record.member_id == user.id
  end
end
