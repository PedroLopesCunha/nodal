# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :context, :user, :organisation, :record

  def initialize(context, record)
    @context = context
    @user = context.is_a?(PunditContext) ? context.user : context
    @organisation = context.is_a?(PunditContext) ? context.organisation : nil
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :context, :user, :organisation, :scope

    def initialize(context, scope)
      @context = context
      @user = context.is_a?(PunditContext) ? context.user : context
      @organisation = context.is_a?(PunditContext) ? context.organisation : nil
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    def user_is_a_member?
      return @user.is_a?(Member)
    end

    def member_working_for_organisation?
      return user_is_a_member? ? @user.organisations.include?(@organisation) : false
    end

    def user_is_a_customer?
      return @user.is_a?(Customer)
    end

    def user_beeing_customer_of_organsiation?
      return user_is_a_customer? ? @user.organisation == @organisation : false
    end
  end

  private

  def user_is_a_member?
    return @user.is_a?(Member)
  end

  def member_working_for_organisation?
    return user_is_a_member? ? @user.organisations.include?(@organisation) : false
  end

  def user_is_a_customer?
    return @user.is_a?(Customer)
  end

  def user_beeing_customer_of_organsiation?
    return user_is_a_customer? ? @user.organisation == @organisation : false
  end

  def record_belongs_to_user_organisation?
    if user_is_a_member?
      return @user.organisations.include?(record.organisation)
    elsif user_is_a_customer?
      return @user.organisation == record.organisation
    else
      return false
    end
  end
end
