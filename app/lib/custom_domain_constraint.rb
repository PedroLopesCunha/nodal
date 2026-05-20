# Route constraint that matches when request.host belongs to an org's
# custom_domain. Used in config/routes.rb to mount the slugless storefront
# routes on custom hosts, and to redirect BO traffic away from them.
class CustomDomainConstraint
  def matches?(request)
    Organisation.find_by_host(request.host).present?
  end
end
