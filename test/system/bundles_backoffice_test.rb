require "application_system_test_case"

class BundlesBackofficeTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1100]
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    page.driver.browser.manage.window.resize_to(1400, 1100)
    @org = Organisation.create!(name: "Bundle UI Review", currency: "EUR")
    @admin = Member.create!(email: "bundle-design@example.com", password: "password123", first_name: "Ana", last_name: "Admin", locale: "pt")
    @org.org_members.create!(member: @admin, role: "owner", active: true)
    @first = @org.products.create!(name: "Colar Aurora", sku: "BND-ABC", unit_price: 15000, published: true)
    @second = @org.products.create!(name: "Brincos Aurora", sku: "BND-XYZ", unit_price: 7000, published: true)
    6.times { |i| @org.products.create!(name: "Colar Aurora #{i}", sku: "BND-EXTRA-#{i}", unit_price: 10000, published: true) }
    @category = @org.categories.create!(name: "Joalharia")
    login_as @admin, scope: :member
  end

  teardown { Warden.test_reset! }

  test "uses the existing BO layout and searchable selectors to create and edit a bundle" do
    visit bo_bundles_path(org_slug: @org.slug, locale: "pt")
    assert_selector ".bo-page-header h1", text: "Conjuntos"
    assert_selector ".bo-page-body .nav-link.active", count: 1
    assert_selector ".bo-page-body .card .card-body", text: "Ainda não existem conjuntos"
    page.save_screenshot("/tmp/nodal-bundles-index.png")

    visit new_bo_bundle_path(org_slug: @org.slug, locale: "pt")
    assert_selector ".bo-page-header button[form='bundle-form']"
    assert_selector ".bo-page-body #bundle-form .ts-wrapper", count: 2
    fill_in "product_name", with: "Conjunto Aurora"
    fill_in "product_price", with: "200.00"
    check "bundle_category_#{@category.id}"

    choose_component(0, "Colar", @first.default_variant.id)
    choose_component(1, "BND-XYZ", @second.default_variant.id)
    find("[data-action='bundle-editor#add']").click
    assert_selector "tbody [data-bundle-editor-target='row']", count: 3
    all("tbody [data-bundle-editor-target='row']").last.find("button").click
    assert_selector "tbody [data-bundle-editor-target='row']", count: 2
    page.save_screenshot("/tmp/nodal-bundles-new.png")
    find(".bo-page-header button[form='bundle-form']").click
    assert_text "Conjunto guardado."
    bundle = @org.products.bundles.sole
    assert_current_path bo_bundle_path(org_slug: @org.slug, id: bundle)
    find(".bo-page-header a[href='#{edit_bo_bundle_path(org_slug: @org.slug, id: bundle)}']").click
    assert_field "product_name", with: "Conjunto Aurora"
    assert_selector "#bundle-form .ts-wrapper", count: 2
    assert_equal 2, @org.products.bundles.sole.bundle_components.count
    page.save_screenshot("/tmp/nodal-bundles-edit.png")

    visit bo_bundles_path(org_slug: @org.slug)
    assert_selector ".bo-page-body .table tbody tr", count: 1
    assert_selector ".bo-page-body .nav-link.active", count: 1
    page.save_screenshot("/tmp/nodal-bundles-list.png")
    page.driver.browser.manage.window.resize_to(390, 844)
    visit edit_bo_bundle_path(org_slug: @org.slug, id: @org.products.bundles.sole.id)
    assert_selector ".bo-page-header button[form='bundle-form']"
    page.save_screenshot("/tmp/nodal-bundles-mobile.png")
  end

  test "uploaded images do not crash validation and the rich description survives a corrected submission" do
    visit new_bo_bundle_path(org_slug: @org.slug)
    assert_selector "trix-editor"
    fill_in "product_name", with: "Conjunto com imagem"
    fill_in "product_price", with: "200.00"
    find("trix-editor").set("Descrição formatada do conjunto")
    choose_component(0, "BND-ABC", @first.default_variant.id)
    all("tbody [data-bundle-editor-target='row']").last.find("button").click
    Tempfile.create(["bundle-photo", ".png"]) do |file|
      file.binmode
      file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1kAAAAASUVORK5CYII="))
      file.flush
      attach_file "product_photos", file.path
      find(".bo-page-header button[form='bundle-form']").click
      assert_selector ".alert-danger"
      assert_selector "trix-editor", text: "Descrição formatada do conjunto"
      assert_text "Volte a selecionar as imagens antes de guardar."
      find("[data-action='bundle-editor#add']").click
      choose_component(1, "BND-XYZ", @second.default_variant.id)
      attach_file "product_photos", file.path
      find(".bo-page-header button[form='bundle-form']").click
      assert_text "Conjunto guardado."
    end
    bundle = @org.products.bundles.sole
    assert_equal 1, bundle.photos.count
    assert_includes bundle.rich_description.to_plain_text, "Descrição formatada do conjunto"
  end

  test "bundle storefront reuses the product presentation for members and customers" do
    @org.product_discounts.create!(product: @first, discount_type: "percentage", discount_value: 0.2)
    bundle = @org.products.create!(name: "Conjunto Aurora", bundle: true, published: true, unit_price: 20000,
      bundle_components_attributes: [@first, @second].map { |product| { product_variant_id: product.default_variant.id, quantity: 1 } })
    visit product_path(org_slug: @org.slug, id: @first.id)
    assert_selector ".product-detail-image-container"
    product_style = page.evaluate_script("(() => {const h = document.querySelector('.card-body.p-4 h1'); const card = h.closest('.card'); return [getComputedStyle(h).fontSize, getComputedStyle(h).fontWeight, getComputedStyle(card).borderRadius]})()")
    visit product_path(org_slug: @org.slug, id: bundle.id)
    assert_selector ".card-body.p-4 h1", text: bundle.name
    assert_selector ".product-detail-image-container"
    assert_selector "[data-bundle-components] .table tbody tr", count: 2
    assert_no_selector "form[action$='/order_bundles']"
    assert_no_selector "input[name='quantity']"
    assert_selector "del[data-product-pricing-target='headerOriginal']", text: /220/
    assert_selector "[data-bundle-savings] strong", text: /20/
    assert_selector "[data-bundle-components] .table thead th", text: "Preço Unitário Conjunto"
    bundle_style = page.evaluate_script("(() => {const h = document.querySelector('.card-body.p-4 h1'); const card = h.closest('.card'); return [getComputedStyle(h).fontSize, getComputedStyle(h).fontWeight, getComputedStyle(card).borderRadius]})()")
    assert_equal product_style, bundle_style
    page.save_screenshot("/tmp/nodal-storefront-bundle-member.png")

    customer = @org.customers.create!(company_name: "Buyer", contact_name: "Buyer", active: true)
    user = customer.customer_users.create!(organisation: @org, email: "bundle-design-buyer@example.com", password: "password123", active: true, locale: "pt")
    logout :member
    login_as user, scope: :customer_user
    visit product_path(org_slug: @org.slug, id: bundle.id)
    assert_selector "button[form='bundle-cart-form'].btn-primary.btn-lg.w-100"
    assert_selector "[data-controller='quantity-stepper']"
    assert_no_selector "del[data-product-pricing-target='headerOriginal']"
    assert_no_selector "[data-bundle-savings]"
    page.save_screenshot("/tmp/nodal-storefront-bundle-customer.png")
    find("button[form='bundle-cart-form'][type='submit']").click
    assert_text "Conjunto adicionado ao carrinho."
    assert_equal 20000, user.current_cart(@org).total_amount.cents
  end

  test "bundle price comparison and included unit prices remain stable after quantity changes" do
    @first.update!(unit_price: 1200)
    @second.update!(unit_price: 2300)
    third = @org.products.create!(name: "Anel Aurora", unit_price: 1200, published: true)
    [@first, third].each { |product| @org.product_discounts.create!(product: product, discount_type: "percentage", discount_value: 0.05) }
    bundle = @org.products.create!(name: "Seven pieces", bundle: true, published: true, unit_price: 9900,
      bundle_components_attributes: [@first, @second, third].zip([2, 3, 2]).map { |product, quantity| { product_variant_id: product.default_variant.id, quantity: quantity } })
    visit product_path(org_slug: @org.slug, id: bundle.id)
    assert_selector "del[data-product-pricing-target='headerOriginal']", text: /117/
    assert_selector "[data-bundle-savings] strong", text: /18/
    assert_selector "[data-bundle-components] .table tbody tr:first-child td:nth-child(4)", text: /10.16/
    page.save_screenshot("/tmp/nodal-bundle-member-comparison.png")
    customer = @org.customers.create!(company_name: "Buyer", contact_name: "Buyer", active: true)
    user = customer.customer_users.create!(organisation: @org, email: "bundle-comparison@example.com", password: "password123", active: true, locale: "pt")
    logout :member
    login_as user, scope: :customer_user
    visit product_path(org_slug: @org.slug, id: bundle.id)
    assert_selector "del[data-product-pricing-target='headerOriginal']", text: /114.60/
    assert_selector "[data-bundle-savings] strong", text: /15.60/
    find("input[name='quantity']").set("2")
    assert_selector "[data-product-pricing-target='total']", text: /198.00/
    assert_selector "del[data-product-pricing-target='headerOriginal']", text: /114.60/
    assert_selector "[data-product-pricing-target='headerPrice']", text: /99.00/
    page.save_screenshot("/tmp/nodal-bundle-customer-comparison.png")
  end

  test "composition summary updates values stock and price difference before saving" do
    @first.default_variant.update!(track_stock: true, stock_quantity: 5)
    @second.default_variant.update!(track_stock: true, stock_quantity: 10)
    visit new_bo_bundle_path(org_slug: @org.slug)
    fill_in "product_name", with: "Resumo do conjunto"
    choose_component(0, "BND-ABC", @first.default_variant.id)
    choose_component(1, "BND-XYZ", @second.default_variant.id)
    assert_selector "[data-bundle-editor-target='total']", text: Money.new(22000, "EUR").format
    assert_selector "[data-bundle-editor-target='stock']", text: "5"
    rows = all("tbody [data-bundle-editor-target='row']", count: 2)
    rows[0].find("input[name$='[quantity]']").set("2")
    rows[1].find("input[name$='[quantity]']").set("3")
    assert_selector "[data-bundle-editor-target='total']", text: Money.new(51000, "EUR").format
    assert_selector "[data-bundle-editor-target='stock']", text: "2"
    fill_in "product_price", with: "450.00"
    assert_selector "[data-bundle-editor-target='difference']", text: Money.new(6000, "EUR").format
    assert_selector "[data-bundle-editor-target='percentage']", text: "11.76%"
    rows[1].find("button").click
    assert_selector "[data-bundle-editor-target='total']", text: Money.new(30000, "EUR").format
    find("[data-action='bundle-editor#add']").click
    choose_component(1, "BND-XYZ", @second.default_variant.id)
    assert_selector "[data-bundle-editor-target='total']", text: Money.new(37000, "EUR").format
    fill_in "product_price", with: "400.00"
    assert_selector "[data-bundle-editor-target='differenceLabel']", text: "Acima do valor dos componentes"
    assert_selector "[data-bundle-editor-target='difference']", text: Money.new(3000, "EUR").format
    page.save_screenshot("/tmp/nodal-bundle-live-summary.png")
    find(".bo-page-header button[form='bundle-form']").click
    assert_text "Conjunto guardado."
    bundle = @org.products.bundles.sole
    assert_current_path bo_bundle_path(org_slug: @org.slug, id: bundle)
    assert_selector ".bo-page-header h1", text: bundle.name
    assert_selector "[data-bundle-stock]", text: "2"
    assert_text Money.new(37000, "EUR").format
    page.save_screenshot("/tmp/nodal-bundle-details.png")
  end

  private

  def choose_component(index, query, id)
    row = all("tbody [data-bundle-editor-target='row']", minimum: index + 1)[index]
    row.find(".ts-control input", wait: 10).set(query)
    option = find(".ts-dropdown .option[data-value='#{id}']", wait: 10)
    assert_equal "BODY", option.evaluate_script("this.closest('.ts-dropdown').parentElement.tagName")
    page.save_screenshot("/tmp/nodal-bundles-picker.png") if index.zero?
    option.click
  end
end
