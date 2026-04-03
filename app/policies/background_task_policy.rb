class BackgroundTaskPolicy < ApplicationPolicy
  def show?
    record_belongs_to_user_organisation?
  end
end
