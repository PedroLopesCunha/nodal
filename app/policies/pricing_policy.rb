class PricingPolicy < ApplicationPolicy
  def index?
    member_working_for_organisation?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
    end
  end
end
