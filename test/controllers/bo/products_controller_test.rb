require "test_helper"

class Bo::ProductsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @organisation = Organisation.create!(name: "Products Catalog Org", currency: "EUR")
    @admin = Member.create!(email: "products-admin@example.com", password: "password123",
                            first_name: "Ana", last_name: "Admin")
    @organisation.org_members.create!(member: @admin, role: "owner", active: true)
    sign_in @admin
  end

  # Regression guard: the catalog modals/partials were parameterized so the
  # sales-rep page can reuse them. The admin flow must keep working with the
  # default (products-scoped) URLs when no locals are passed.
  test "admin products index renders the catalog modals" do
    get bo_products_path(org_slug: @organisation.slug)
    assert_response :success
  end

  test "admin catalog selection partial renders" do
    get catalog_selection_bo_products_path(org_slug: @organisation.slug)
    assert_response :success
  end
  test "product search matches attributes of simple and unpublished variable products" do
    attribute = @organisation.product_attributes.create!(name: "Cor", display_type: "dropdown", card_display_mode: "values")
    value = attribute.product_attribute_values.create!(value: "Encarnádo exclusivo")
    simple = @organisation.products.create!(name: "Produto Simples", unit_price: 1000)
    simple.default_variant.attribute_values << value
    variable = @organisation.products.create!(name: "Produto Variavel", has_variants: true, published: false)
    variant = variable.product_variants.create!(organisation: @organisation, name: "Opcao", is_default: false, published: false)
    variant.attribute_values << value
    other = @organisation.products.create!(name: "Outro Produto", unit_price: 1000)

    get bo_products_path(org_slug: @organisation.slug, query: "encarnado exclusivo")
    assert_response :success
    assert_select ".product-row", count: 2
    assert_select ".product-row", text: /Produto Simples/, count: 1
    assert_select ".product-row", text: /Produto Variavel/, count: 1
    assert_select ".product-row", text: /Outro Produto/, count: 0
  end

  test "product search still matches description" do
    @organisation.products.create!(name: "Produto", unit_price: 1000, description: "acabamento singularissimo")
    get bo_products_path(org_slug: @organisation.slug, query: "singularissimo")
    assert_response :success
    assert_select ".product-row", count: 1
  end

  test "owner can queue one product ERP sync without leaving the product page" do
    @organisation.create_erp_configuration!(adapter_type: "custom_api", enabled: true, sync_products: true,
      product_sync_mode: "update_only", credentials: { base_url: "https://erp.example.test", api_key: "test" })
    product = @organisation.products.create!(name: "Sync Product", sku: "ERP-1", unit_price: 1000)
    get bo_product_path(org_slug: @organisation.slug, id: product.id)
    assert_response :success
    assert_select "form[action='#{sync_erp_bo_product_path(org_slug: @organisation.slug, id: product.id)}']", count: 1

    assert_enqueued_with(job: ErpProductSyncJob) do
      post sync_erp_bo_product_path(org_slug: @organisation.slug, id: product.id), as: :json
    end
    task = @organisation.background_tasks.last
    assert_equal "erp_product_sync", task.task_type
    assert_equal product.id, task.result["product_id"]
    assert_response :accepted
    assert_equal bo_background_task_path(org_slug: @organisation.slug, id: task.id, format: :json), response.parsed_body["status_url"]
    get bo_background_task_path(org_slug: @organisation.slug, id: task.id)
    assert_response :success
    assert_select "[data-task-progress-redirect-value='#{bo_product_path(org_slug: @organisation.slug, id: product.id)}']", count: 1
  end

  test "ERP sync cannot be queued without an active integration" do
    product = @organisation.products.create!(name: "Local", unit_price: 1000)
    assert_no_difference "BackgroundTask.count" do
      assert_no_enqueued_jobs do
        post sync_erp_bo_product_path(org_slug: @organisation.slug, id: product.id)
      end
    end
    assert_redirected_to bo_product_path(org_slug: @organisation.slug, id: product.id)
  end

  test "ordinary members cannot trigger product ERP synchronization" do
    @organisation.org_members.find_by!(member: @admin).update!(role: "member")
    product = @organisation.products.create!(name: "Product", unit_price: 1000)
    assert_not ProductPolicy.new(@admin, product).sync_erp?
    assert_no_enqueued_jobs do
      assert_raises(Pundit::NotAuthorizedError) do
        post sync_erp_bo_product_path(org_slug: @organisation.slug, id: product.id)
      end
    end
    assert_equal 0, @organisation.background_tasks.count
  end

  test "product page renders even when ERP credentials cannot be decrypted" do
    config = @organisation.create_erp_configuration!(adapter_type: "custom_api", enabled: true, sync_products: true,
      product_sync_mode: "update_only", credentials: { base_url: "https://erp.example.test", api_key: "test" })
    ActiveRecord::Base.connection.execute("UPDATE erp_configurations SET credentials_ciphertext = 'unreadable' WHERE id = #{config.id}")
    product = @organisation.products.create!(name: "Product", unit_price: 1000)
    get bo_product_path(org_slug: @organisation.slug, id: product.id)
    assert_response :success
    assert_select "form[action='#{sync_erp_bo_product_path(org_slug: @organisation.slug, id: product.id)}']", count: 1
  end

end
