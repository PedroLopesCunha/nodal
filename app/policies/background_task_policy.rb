class BackgroundTaskPolicy < ApplicationPolicy
  def index?
    user_is_a_member?
  end

  def show?
    record_belongs_to_user_organisation?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organisation: organisation)
    end
  end
end
