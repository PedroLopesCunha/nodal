require "test_helper"

class BundlesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Bundle UI", currency: "EUR")
    @customer = @org.customers.create!(company_name: "Buyer", contact_name: "Buyer", active: true)
    @user = @customer.customer_users.create!(organisation: @org, email: "bundle-ui@example.com", password: "password123", active: true)
    @first = @org.products.create!(name: "Colar", sku: "COLAR", unit_price: 15000, published: true)
    @second = @org.products.create!(name: "Brincos", sku: "BRINCOS", unit_price: 7000, published: true)
    @bundle = @org.products.create!(name: "Conjunto Aurora", bundle: true, published: true, bundle_featured: true,
      unit_price: 20000, bundle_components_attributes: [@first, @second].map { |p| { product_variant_id: p.default_variant.id, quantity: 1 } })
    @admin = Member.create!(email: "bundle-admin@example.com", password: "password123", first_name: "Bundle", last_name: "Admin")
    @org.org_members.create!(member: @admin, role: "owner", active: true)
  end

  test "bundle stock follows the product quantity permission and display settings" do
    sign_in @user
    @org.update!(show_product_availability: true, storefront_stock_display: "exact")
    [@first, @second].each { |product| product.default_variant.update!(track_stock: true, stock_quantity: 17, stock_policy: "hide") }
    @bundle.reload.refresh_bundle_inventory!
    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_select "[data-bundle-availability]", count: 1
    assert_select "[data-bundle-stock]", count: 0
    @customer.update!(sees_stock_quantities: true)
    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_select "[data-bundle-stock]", text: /17/
    @org.update!(storefront_stock_display: "bands", low_stock_threshold: 20)
    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_select "[data-bundle-stock]", text: I18n.t("storefront.products.show.stock_low")
    @org.update!(show_product_availability: false)
    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_select "[data-bundle-availability]", count: 0
  end

  test "back office lists edits searches and creates bundles" do
    sign_in @admin
    get bo_bundles_path(org_slug: @org.slug)
    assert_response :success
    assert_select ".bo-page-header h1"
    assert_select ".bo-page-body .nav-link.active", count: 1
    get new_bo_bundle_path(org_slug: @org.slug)
    assert_response :success
    assert_select 'input[name="product[price]"]'
    assert_select ".bo-page-header button[form='bundle-form']"
    assert_select ".bo-page-body form#bundle-form tbody select[data-controller='tom-select']", count: 2
    assert_select "[data-controller='checkbox-select']"
    assert_select "trix-editor"
    assert_select "input[name='product[rich_description]']"
    get edit_bo_bundle_path(org_slug: @org.slug, id: @bundle.id)
    assert_response :success
    get components_bo_bundles_path(org_slug: @org.slug, q: "COLAR")
    assert_response :success
    assert_equal [@first.default_variant.id], response.parsed_body.map { |v| v["id"] }
    assert_difference "Product.bundles.count" do
      post bo_bundles_path(org_slug: @org.slug), params: { product: { name: "New set", price: "190.99", published: "1",
        bundle_components_attributes: { "0" => { product_variant_id: @first.default_variant.id, quantity: 1 }, "1" => { product_variant_id: @second.default_variant.id, quantity: 2 } } } }
    end
    assert_response :redirect
    bundle = @org.products.bundles.order(:id).last
    assert_equal 19099, bundle.unit_price
    assert_equal [1, 2], bundle.bundle_components.order(:id).pluck(:quantity)
  end

  test "storefront discovers bundles and purchases them as a group" do
    sign_in @user
    get home_path(org_slug: @org.slug)
    assert_response :success
    assert_select "a[href*='bundles=1']"
    get products_path(org_slug: @org.slug, bundles: "1")
    assert_response :success
    assert_select ".product-card-title", text: @bundle.name
    assert_select ".product-card-title", text: @first.name, count: 0
    get products_path(org_slug: @org.slug)
    assert_select ".product-card-image [data-bundle-opportunity]", text: I18n.t("bundles.available_badge")
    assert_select 'a[href$="#product-bundles"]', count: 0

    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_response :success
    assert_select 'form[action$="/order_bundles"]'
    assert_select ".product-detail-image-container"
    assert_select ".col-lg-6 .card .card-body.p-4 h1", text: @bundle.name
    assert_select "[data-bundle-components] .table tbody tr", count: 2
    assert_select "button.btn-primary.btn-lg.w-100"
    get product_path(org_slug: @org.slug, id: @first.id)
    assert_response :success
    assert_select "#product-bundles"
    post order_bundles_path(org_slug: @org.slug), params: { product_id: @bundle.id, quantity: 2 }
    assert_redirected_to cart_path(org_slug: @org.slug)
    follow_redirect!
    assert_response :success
    assert_select "h2", text: @bundle.name
    cart = @user.current_cart(@org)
    group = cart.order_bundles.sole
    assert_equal 40000, cart.total_amount.cents
    get checkout_path(org_slug: @org.slug)
    assert_response :success
    assert_select "h3", text: /#{@bundle.name}/
    patch order_bundle_path(org_slug: @org.slug, id: group.id), params: { quantity: 3 }
    assert_equal 3, group.reload.quantity
    assert_equal [3, 3], group.order_items.pluck(:quantity)
    patch order_item_path(org_slug: @org.slug, id: group.order_items.first.id), params: { order_item: { quantity: 99 } }
    assert_response :not_found
    delete order_bundle_path(org_slug: @org.slug, id: group.id)
    assert_empty cart.order_items.reload
  end

  test "placed orders show their saved bundle and reorder using the current definition" do
    sign_in @user
    cart = @user.current_cart(@org)
    group = BundleCartService.new(cart).add!(@bundle, 1)
    cart.place!
    @bundle.update!(name: "Updated bundle", unit_price: 19000)
    get order_path(org_slug: @org.slug, id: cart.id)
    assert_response :success
    assert_select "h3", text: /Conjunto Aurora/
    assert_equal 20000, group.reload.total_price.cents
    post add_to_cart_order_path(org_slug: @org.slug, id: cart.id)
    assert_response :redirect
    current = @user.current_cart(@org)
    assert_equal "Updated bundle", current.order_bundles.sole.name
    assert_equal 19000, current.reload.total_amount.cents
  end

  test "bundle source and component picker are tenant scoped" do
    other = Organisation.create!(name: "Other bundle shop")
    outsider = other.products.create!(name: "Secret", sku: "SECRET", unit_price: 100)
    sign_in @admin
    get components_bo_bundles_path(org_slug: @org.slug, q: "SECRET")
    assert_equal [], response.parsed_body
    assert_no_difference "Product.bundles.count" do
      post bo_bundles_path(org_slug: @org.slug), params: { product: { name: "Invalid set", price: 100,
        bundle_components_attributes: { "0" => { product_variant_id: outsider.default_variant.id, quantity: 1 }, "1" => { product_variant_id: @first.default_variant.id, quantity: 1 } } } }
    end
    assert_response :not_found
  end

  test "member bundle view uses the product page without an orphan quantity field" do
    sign_in @admin
    get product_path(org_slug: @org.slug, id: @bundle.id)
    assert_response :success
    assert_select ".product-detail-image-container"
    assert_select ".col-lg-6 .card .card-body.p-4 h1", text: @bundle.name
    assert_select "[data-bundle-components] .table tbody tr", count: 2
    assert_select 'form[action$="/order_bundles"]', count: 0
    assert_select "input[name='quantity']", count: 0
  end

  test "member comparison is base price and shows savings and included unit prices" do
    @org.product_discounts.create!(product: @first, discount_type: "percentage", discount_value: 0.2)
    sign_in @admin
    get product_path(org_slug: @org.slug, id: @bundle)
    assert_response :success
    assert_select "del[data-product-pricing-target='headerOriginal']", text: /220/
    assert_select "[data-bundle-savings] strong", text: /20/
    assert_select "[data-bundle-components] .table thead th", text: I18n.t("bundles.unit_in_bundle")
    assert_select "[data-bundle-components] .table tbody tr:first-child td:nth-child(3)", text: /150/
    assert_select "[data-bundle-components] .table tbody tr:first-child td:nth-child(4)", text: /136.36/
  end

  test "back office bundle has a detail page and a live composition preview" do
    sign_in @admin
    get bo_bundle_path(org_slug: @org.slug, id: @bundle)
    assert_response :success
    assert_select ".bo-page-header h1", text: @bundle.name
    assert_select "a[href='#{edit_bo_bundle_path(org_slug: @org.slug, id: @bundle)}']"
    get bo_product_path(org_slug: @org.slug, id: @bundle)
    assert_redirected_to bo_bundle_path(org_slug: @org.slug, id: @bundle)
    @first.default_variant.update!(track_stock: true, stock_quantity: 5)
    @second.default_variant.update!(track_stock: true, stock_quantity: 10)
    assert_no_difference ["Product.count", "BundleComponent.count", "OrderItem.count"] do
      post preview_bo_bundles_path(org_slug: @org.slug), params: { price: "450.00", components: [
        { product_variant_id: @first.default_variant.id, quantity: 2 }, { product_variant_id: @second.default_variant.id, quantity: 3 }
      ] }, as: :json
    end
    assert_response :success
    assert_equal 51000, response.parsed_body["total_cents"]
    assert_equal 2, response.parsed_body["capacity"]
    assert_equal 6000, response.parsed_body["difference_cents"]
    assert_equal 11.76, response.parsed_body["percentage"]
    post preview_bo_bundles_path(org_slug: @org.slug), params: { components: [{ product_variant_id: @first.default_variant.id, quantity: 0 }] }, as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
  end

  test "invalid create with an uploaded image renders validation errors without signing a new blob" do
    sign_in @admin
    with_uploaded_image do |upload|
      assert_no_difference "Product.bundles.count" do
        post bo_bundles_path(org_slug: @org.slug), params: { product: { name: "Invalid photo set", price: 200,
          rich_description: "<p>Formatted <strong>description</strong></p>", photos: [upload],
          bundle_components_attributes: { "0" => { product_variant_id: @first.default_variant.id, quantity: 0 },
            "1" => { product_variant_id: @second.default_variant.id, quantity: 1 } } } }
      end
      assert_response :unprocessable_entity
      assert_select ".alert-danger"
      assert_select "input[name='product[name]'][value='Invalid photo set']"
      assert_select "trix-editor"
      assert_select "[role='status']", text: I18n.t("bundles.reselect_photos")
    end
  end

  test "valid bundle saves image and formatted description and allows editing them" do
    sign_in @admin
    with_uploaded_image do |upload|
      post bo_bundles_path(org_slug: @org.slug), params: { product: { name: "Photo set", price: 200,
        rich_description: "<p>Formatted <strong>description</strong></p>", photos: [upload],
        bundle_components_attributes: { "0" => { product_variant_id: @first.default_variant.id, quantity: 1 },
          "1" => { product_variant_id: @second.default_variant.id, quantity: 1 } } } }
    end
    assert_response :redirect
    bundle = @org.products.bundles.order(:id).last
    assert_equal 1, bundle.photos.count
    assert_includes bundle.rich_description.to_s, "<strong>description</strong>"
    get edit_bo_bundle_path(org_slug: @org.slug, id: bundle.id)
    assert_response :success
    assert_select "img[alt='Photo set']"
    patch bo_bundle_path(org_slug: @org.slug, id: bundle.id), params: { product: { rich_description: "<p>Updated <em>description</em></p>" } }
    assert_response :redirect
    assert_includes bundle.reload.rich_description.to_s, "<em>description</em>"
  end

  private

  def with_uploaded_image
    Tempfile.create(["bundle-photo", ".png"]) do |file|
      file.binmode
      file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1kAAAAASUVORK5CYII="))
      file.flush
      yield Rack::Test::UploadedFile.new(file.path, "image/png")
    end
  end
end
