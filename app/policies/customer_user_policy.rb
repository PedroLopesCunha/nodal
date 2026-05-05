class CustomerUserPolicy < ApplicationPolicy
  def index?
    member_working_for_organisation?
  end

  def new?
    member_working_for_organisation?
  end

  def create?
    member_working_for_organisation?
  end

  def edit?
    record_belongs_to_user_organisation?
  end

  def update?
    record_belongs_to_user_organisation?
  end

  def toggle_active?
    record_belongs_to_user_organisation?
  end

  # Resending an invitation only makes sense before the user accepts it.
  def resend_invitation?
    record_belongs_to_user_organisation? && record.invitation_status != :active
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user_is_a_member?
        scope.where(organisation: @organisation)
      else
        scope.none
      end
    end
  end

  private

  # CustomerUser exposes organisation directly via belongs_to.
  def record_belongs_to_user_organisation?
    user_is_a_member? && @user.organisations.include?(record.organisation)
  end
end
