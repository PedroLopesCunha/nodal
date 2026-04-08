class GenerateCatalogJob < ApplicationJob
  include Trackable

  queue_as :default

  def perform(task_id, organisation_id:, product_ids: nil, category_ids: nil, options: {})
    find_task(task_id)
    organisation = Organisation.find(organisation_id)

    # Query products
    products = organisation.products
      .includes(:categories, :product_variants, product_variants: :attribute_values)
      .with_attached_photos

    if product_ids.present?
      products = products.where(id: product_ids)
    elsif category_ids.present?
      product_ids_from_cats = CategoryProduct.where(category_id: category_ids).select(:product_id)
      products = products.where(id: product_ids_from_cats)
    end

    products = products.where(published: true) if options["only_available"] != "0"

    case options["sort_by"]
    when "price" then products = products.order(:unit_price)
    else products = products.order(:name)
    end

    # Generate PDF via chunked service
    service = CatalogPdfService.new(
      products: products,
      organisation: organisation,
      options: options
    )

    pdf = service.generate do |progress, total|
      update_progress(progress, total)
    end

    # Upload PDF to Cloudinary as raw file (not image)
    catalog_title = options["catalog_title"].presence || organisation.name
    filename = "#{catalog_title.parameterize}_#{Date.today.iso8601}.pdf"

    tempfile = Tempfile.new([filename, ".pdf"], binmode: true)
    tempfile.write(pdf)
    tempfile.rewind

    result = Cloudinary::Uploader.upload(
      tempfile.path,
      resource_type: "raw",
      folder: "#{Rails.env}/catalogs",
      public_id: filename.sub(".pdf", ""),
      overwrite: true,
      type: "upload"
    )
    tempfile.close!

    save_result({
      filename: filename,
      product_count: products.size,
      cloudinary_public_id: result["public_id"],
      cloudinary_url: result["secure_url"]
    })
  end
end
