class GenerateCatalogJob < ApplicationJob
  include Trackable

  queue_as :default

  def perform(task_id, organisation_id:, product_ids: nil, category_ids: nil, options: {})
    find_task(task_id)
    organisation = Organisation.find(organisation_id)

    update_progress(0, 3) # 3 steps: query, render, generate

    # Step 1: Query products
    products = organisation.products
      .includes(:categories, :product_variants, product_variants: :attribute_values)
      .with_attached_photos

    if product_ids.present?
      products = products.where(id: product_ids)
    elsif category_ids.present?
      product_ids_from_cats = CategoryProduct.where(category_id: category_ids).select(:product_id)
      products = products.where(id: product_ids_from_cats)
    end

    products = products.where(available: true) if options["only_available"] != "0"

    case options["sort_by"]
    when "price" then products = products.order(:unit_price)
    else products = products.order(:name)
    end

    update_progress(1)

    # Step 2: Render HTML
    catalog_title = options["catalog_title"].presence || organisation.name
    renderer = ApplicationController.renderer.new

    html = renderer.render(
      template: "shared/catalog/pdf",
      layout: false,
      assigns: {
        products: products,
        catalog_title: catalog_title,
        show_prices: options["show_prices"] != "0",
        show_sku: options["show_sku"] == "1",
        show_description: options["show_description"] == "1",
        show_variants: options["show_variants"] == "1",
        show_variant_sku: options["show_variant_sku"] == "1",
        show_variant_price: options["show_variant_price"] == "1",
        show_variant_photo: options["show_variant_photo"] == "1",
        layout: options["catalog_layout"] == "list" ? "list" : "grid",
        group_by_category: options["group_by_category"] == "1",
        organisation: organisation,
        catalog_host: options["base_url"] || "http://localhost:3000"
      }
    )

    update_progress(2)

    # Step 3: Generate PDF
    pdf = Grover.new(html, format: "A4", print_background: true).to_pdf
    filename = "#{catalog_title.parameterize}_#{Date.today.iso8601}.pdf"

    @background_task.file.attach(
      io: StringIO.new(pdf),
      filename: filename,
      content_type: "application/pdf"
    )

    save_result({ filename: filename, product_count: products.size })
    update_progress(3)
  end
end
