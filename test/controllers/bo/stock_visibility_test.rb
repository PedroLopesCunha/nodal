require "test_helper"

# Managing which companies see stock quantities. A customer category is a way
# to select every company in it at once — what gets stored is always companies,
# so a customer reclassified later does not gain access on its own.
class Bo::StockVisibilityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Visibility BO Org", currency: "EUR",
                                storefront_stock_display: "exact")
    @admin = Member.create!(email: "vis-admin@example.com", password: "password123",
                            first_name: "Ana", last_name: "Admin")
    @org.org_members.create!(member: @admin, role: "owner", active: true)
    sign_in @admin

    @partners = @org.customer_categories.create!(name: "Parceiros")
    @alpha = company("Alpha Lda", category: @partners)
    @beta = company("Beta Lda", category: @partners)
    @gamma = company("Gamma Lda")
  end

  def company(name, category: nil)
    @org.customers.create!(company_name: name, contact_name: "Rui", active: true,
                           customer_category: category)
  end

  def save_permitted(ids)
    patch bo_stock_visibility_path(org_slug: @org.slug), params: { customer_ids: ids.map(&:to_s) }
  end

  test "the page lists the companies already permitted" do
    @alpha.update!(sees_stock_quantities: true)

    get bo_stock_visibility_path(org_slug: @org.slug)

    assert_response :success
    assert_select "[data-customer-id='#{@alpha.id}']"
    assert_select "[data-customer-id='#{@gamma.id}']", 0
  end

  test "saving permits exactly the companies submitted" do
    save_permitted([ @alpha.id, @gamma.id ])

    assert @alpha.reload.sees_stock_quantities?
    assert @gamma.reload.sees_stock_quantities?
    assert_not @beta.reload.sees_stock_quantities?
  end

  # The form submits the whole list, so leaving a company out is how it is
  # removed — there is no separate delete to get out of step with the rest.
  test "a company left out loses the permission" do
    @alpha.update!(sees_stock_quantities: true)
    @beta.update!(sees_stock_quantities: true)

    save_permitted([ @alpha.id ])

    assert @alpha.reload.sees_stock_quantities?
    assert_not @beta.reload.sees_stock_quantities?
  end

  test "saving an empty list permits nobody" do
    @alpha.update!(sees_stock_quantities: true)

    save_permitted([])

    assert_not @alpha.reload.sees_stock_quantities?
  end

  test "one organisation cannot permit another's companies" do
    other_org = Organisation.create!(name: "Outra Org", currency: "EUR", storefront_stock_display: "exact")
    stranger = other_org.customers.create!(company_name: "Estranha Lda", contact_name: "X", active: true)

    save_permitted([ stranger.id ])

    assert_not stranger.reload.sees_stock_quantities?
  end

  test "the picker offers every company in a category" do
    get company_picker_bo_stock_visibility_path(org_slug: @org.slug, customer_category_id: @partners.id)

    assert_response :success
    assert_select "[data-customer-id='#{@alpha.id}']"
    assert_select "[data-customer-id='#{@beta.id}']"
    assert_select "[data-customer-id='#{@gamma.id}']", 0
  end

  test "the picker searches companies by name" do
    get company_picker_bo_stock_visibility_path(org_slug: @org.slug, query: "Gamma")

    assert_response :success
    assert_select "[data-customer-id='#{@gamma.id}']"
    assert_select "[data-customer-id='#{@alpha.id}']", 0
  end

  # The category is a shortcut for selecting, never a stored rule: a company
  # added to the category afterwards has no permission until someone says so.
  test "a company added to a permitted category later is not permitted" do
    save_permitted([ @alpha.id, @beta.id ])

    latecomer = company("Delta Lda", category: @partners)

    assert_not latecomer.reload.sees_stock_quantities?
  end

  test "the page is refused while the organisation shows no quantities" do
    @org.update!(storefront_stock_display: "none")

    get bo_stock_visibility_path(org_slug: @org.slug)

    assert_redirected_to edit_bo_settings_path(org_slug: @org.slug)
  end

  # Same authority as editing the settings: admin or owner. Pundit's rescue is
  # commented out application-wide, so refusal is an exception rather than a
  # redirect — documented here as it is, not as it might be.
  test "a member who cannot edit settings cannot manage this" do
    plain = Member.create!(email: "vis-plain@example.com", password: "password123",
                           first_name: "Zé", last_name: "Membro")
    @org.org_members.create!(member: plain, role: "member", active: true)
    sign_in plain

    assert_raises(Pundit::NotAuthorizedError) do
      get bo_stock_visibility_path(org_slug: @org.slug)
    end
  end

  test "a member who cannot edit settings cannot save either" do
    plain = Member.create!(email: "vis-plain2@example.com", password: "password123",
                           first_name: "Zé", last_name: "Membro")
    @org.org_members.create!(member: plain, role: "member", active: true)
    sign_in plain

    assert_raises(Pundit::NotAuthorizedError) { save_permitted([ @alpha.id ]) }
    assert_not @alpha.reload.sees_stock_quantities?
  end
  # "Add all" is a snapshot, exactly like the category buttons: it permits the
  # companies that exist when it is pressed, and says nothing about the future.
  test "the all-companies list carries every company in the organisation" do
    get all_companies_bo_stock_visibility_path(org_slug: @org.slug)

    assert_response :success
    ids = JSON.parse(response.body).map { |c| c["id"] }
    assert_equal [ @alpha.id, @beta.id, @gamma.id ].sort, ids.sort
  end

  test "the all-companies list carries a name to show" do
    get all_companies_bo_stock_visibility_path(org_slug: @org.slug)

    alpha = JSON.parse(response.body).find { |c| c["id"] == @alpha.id }
    assert_equal "Alpha Lda", alpha["name"]
    assert_match(/Parceiros/, alpha["subtitle"])
  end

  test "the all-companies list never reaches into another organisation" do
    other_org = Organisation.create!(name: "Outra Org", currency: "EUR", storefront_stock_display: "exact")
    other_org.customers.create!(company_name: "Estranha Lda", contact_name: "X", active: true)

    get all_companies_bo_stock_visibility_path(org_slug: @org.slug)

    names = JSON.parse(response.body).map { |c| c["name"] }
    assert_not_includes names, "Estranha Lda"
  end

  # The snapshot again, from the other side: permitting everyone today leaves
  # tomorrow's company out until someone decides.
  test "a company created after permitting everyone is not permitted" do
    save_permitted([ @alpha.id, @beta.id, @gamma.id ])

    newcomer = company("Delta Lda")

    assert_not newcomer.reload.sees_stock_quantities?
  end

  test "a member who cannot edit settings cannot list every company" do
    plain = Member.create!(email: "vis-plain3@example.com", password: "password123",
                           first_name: "Zé", last_name: "Membro")
    @org.org_members.create!(member: plain, role: "member", active: true)
    sign_in plain

    assert_raises(Pundit::NotAuthorizedError) do
      get all_companies_bo_stock_visibility_path(org_slug: @org.slug)
    end
  end
end
