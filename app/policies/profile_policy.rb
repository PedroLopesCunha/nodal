class ProfilePolicy < ApplicationPolicy
  # Members can only edit their own profile
  def update?
    member_working_for_organisation? && user == record
  end
end
