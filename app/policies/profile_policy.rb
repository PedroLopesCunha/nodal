class ProfilePolicy < ApplicationPolicy
  # Members can only edit their own profile
  def update?
    user == record
  end
end
