class ProductPolicy < ApplicationPolicy
  # NOTE: Up to Pundit v2.3.1, the inheritance was declared as
  # `Scope < Scope` rather than `Scope < ApplicationPolicy::Scope`.
  # In most cases the behavior will be identical, but if updating existing
  # code, beware of possible changes to the ancestors:
  # https://gist.github.com/Burgestrand/4b4bc22f31c8a95c425fc0e30d7ef1f5

  def show?
    member_working_for_organisation? && record_belongs_to_user_organisation?
  end

  def show_storefront?
    (member_working_for_organisation? || user_beeing_customer_of_organsiation?) &&
      record_belongs_to_user_organisation?
  end

  def new?
    member_working_for_organisation?
  end

  def create?
    member_working_for_organisation? && record_belongs_to_user_organisation?
  end

  def update?
    member_working_for_organisation? && record_belongs_to_user_organisation?
  end

  def destroy?
    member_working_for_organisation? && record_belongs_to_user_organisation?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      raise Pundit::NotAuthorizedError unless member_working_for_organisation? ||
                                              user_beeing_customer_of_organsiation?

      scope.where(organisation: @organisation)
    end
  end
end
