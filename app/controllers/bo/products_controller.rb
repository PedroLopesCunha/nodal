require "csv"
require "roo"

class Bo::ProductsController < Bo::BaseController
  include Exportable

  before_action :set_product, only: [:show, :edit, :update, :destroy, :configure_variants, :update_variant_configuration, :delete_photo, :set_main_photo, :related_products, :update_related_products, :reorder_related_products]
  before_action :load_attributes_for_form, only: [:new, :edit, :create, :update]

  # Add products choice page
  def add_products
    authorize Product, :add_products?
  end

  # Bulk create with spreadsheet grid
  def bulk_create
    authorize Product, :bulk_create?
    @categories = current_organisation.categories.kept.sorted_by_full_path
    @product_attributes = current_organisation.product_attributes.kept.active.by_position
                            .includes(:product_attribute_values)
    @all_skus = current_organisation.products.pluck(:sku).compact
    @variable_skus = current_organisation.products.where(has_variants: true).pluck(:sku).compact
  end

  def bulk_create_process
    authorize Product, :bulk_create_process?
    raw_rows = params.require(:rows)
    rows = raw_rows.to_unsafe_h.values.map(&:to_h)

    # Handle photo uploads
    zip_path = nil
    images_dir = nil
    import_key = SecureRandom.uuid

    if params[:zip_file].present?
      zip_path = Rails.root.join("tmp", "imports", "#{import_key}.zip").to_s
      FileUtils.mkdir_p(File.dirname(zip_path))
      File.open(zip_path, "wb") { |f| f.write(params[:zip_file].read) }
    end

    if params[:image_files].present?
      images_dir = Rails.root.join("tmp", "imports", "images_#{import_key}").to_s
      FileUtils.mkdir_p(images_dir)
      params[:image_files].each do |image|
        safe_name = image.original_filename.tr("/:", "--")
        File.open(File.join(images_dir, safe_name), "wb") { |f| f.write(image.read) }
      end
    end

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "product_grid_import",
      status: :pending,
      total: rows.size
    )

    ProductGridImportJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      rows: rows,
      zip_path: zip_path,
      images_dir: images_dir,
      photo_mode: params[:photo_mode] || "append"
    )

    redirect_to bo_background_task_path(params[:org_slug], task)
  end

  # Bulk photo upload
  def bulk_photos
    authorize Product, :bulk_photos?
    @all_skus = current_organisation.products.pluck(:sku).compact_blank +
                current_organisation.product_variants.where.not(sku: [nil, ""]).pluck(:sku)
  end

  def bulk_photos_process
    authorize Product, :bulk_photos_process?

    zip_path = nil
    images_dir = nil
    import_key = SecureRandom.uuid
    photo_mode = params[:photo_mode] || "append"

    if params[:zip_file].present?
      zip_path = Rails.root.join("tmp", "imports", "#{import_key}.zip").to_s
      FileUtils.mkdir_p(File.dirname(zip_path))
      File.open(zip_path, "wb") { |f| f.write(params[:zip_file].read) }
    end

    if params[:image_files].present?
      images_dir = Rails.root.join("tmp", "imports", "images_#{import_key}").to_s
      FileUtils.mkdir_p(images_dir)
      params[:image_files].each do |image|
        safe_name = image.original_filename.tr("/:", "--")
        File.open(File.join(images_dir, safe_name), "wb") { |f| f.write(image.read) }
      end
    end

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "bulk_photo_import",
      status: :pending
    )

    BulkPhotoJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      zip_path: zip_path,
      images_dir: images_dir,
      photo_mode: photo_mode
    )

    redirect_to bo_background_task_path(params[:org_slug], task)
  end

  # Import actions
  def import
    authorize Product, :import?
    @categories = current_organisation.categories.kept.sorted_by_full_path
    @all_skus = current_organisation.products.pluck(:sku).compact_blank +
                current_organisation.product_variants.where.not(sku: [nil, ""]).pluck(:sku)
  end

  def import_mapping
    authorize Product, :import?

    unless params[:file].present?
      redirect_to import_bo_products_path(params[:org_slug]), alert: t("bo.products.import.no_file")
      return
    end

    begin
      uploaded_file = params[:file]
      csv_content = parse_uploaded_file(uploaded_file)

      # Auto-detect delimiter (semicolon common in European Excel exports)
      col_sep = detect_csv_delimiter(csv_content)

      # Parse CSV to get headers
      csv = CSV.parse(csv_content, headers: true, col_sep: col_sep)
      @csv_headers = csv.headers.compact.reject(&:blank?)
      @preview_row = csv.first&.to_h || {}

      # Store CSV content in temp file and delimiter in session
      @import_key = SecureRandom.uuid
      temp_path = Rails.root.join("tmp", "imports", "#{@import_key}.csv")
      FileUtils.mkdir_p(temp_path.dirname)
      File.write(temp_path, csv_content)
      session["import_#{@import_key}_col_sep"] = col_sep

      # Store ZIP file if provided
      if params[:zip_file].present?
        zip_path = Rails.root.join("tmp", "imports", "#{@import_key}.zip")
        File.open(zip_path, "wb") { |f| f.write(params[:zip_file].read) }
        session["import_#{@import_key}_zip"] = zip_path.to_s
      end

      # Store individual image files if provided
      if params[:image_files].present?
        images_dir = Rails.root.join("tmp", "imports", "images_#{@import_key}")
        FileUtils.mkdir_p(images_dir)
        params[:image_files].each do |image|
          File.open(images_dir.join(image.original_filename), "wb") { |f| f.write(image.read) }
        end
        session["import_#{@import_key}_images_dir"] = images_dir.to_s
      end

      # Pass through category and photo mode selections
      session["import_#{@import_key}_category_id"] = params[:category_id] if params[:category_id].present?
      session["import_#{@import_key}_photo_mode"] = params[:photo_mode] || "append"

      @importable_fields = ProductImportService.importable_fields
    rescue CSV::MalformedCSVError => e
      redirect_to import_bo_products_path(params[:org_slug]), alert: t("bo.products.import.invalid_csv", error: e.message)
    end
  end

  def import_process
    authorize Product, :import?

    import_key = params[:import_key]
    mapping = params[:mapping]&.to_unsafe_h || {}

    temp_path = Rails.root.join("tmp", "imports", "#{import_key}.csv")

    unless File.exist?(temp_path)
      redirect_to import_bo_products_path(params[:org_slug]), alert: t("bo.products.import.session_expired")
      return
    end

    csv_content = File.read(temp_path)
    col_sep = session["import_#{import_key}_col_sep"] || ","
    zip_path = session["import_#{import_key}_zip"]
    images_dir = session["import_#{import_key}_images_dir"]
    category_id = session["import_#{import_key}_category_id"]
    photo_mode = session["import_#{import_key}_photo_mode"] || "append"

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "product_csv_import",
      status: :pending
    )

    ProductImportJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      csv_content: csv_content,
      column_mapping: mapping,
      col_sep: col_sep,
      zip_path: zip_path,
      images_dir: images_dir,
      photo_mode: photo_mode,
      form_category_id: category_id
    )

    # Clean up session (temp files cleaned by job)
    File.delete(temp_path) if File.exist?(temp_path)
    session.delete("import_#{import_key}_col_sep")
    session.delete("import_#{import_key}_zip")
    session.delete("import_#{import_key}_images_dir")
    session.delete("import_#{import_key}_category_id")
    session.delete("import_#{import_key}_photo_mode")

    redirect_to bo_background_task_path(params[:org_slug], task)
  end

  def index
    @products = apply_product_filters(policy_scope(current_organisation.products).includes(:categories, :product_variants).with_attached_photos)

    # Sorting
    @sort_column = %w[name sku unit_price has_variants published].include?(params[:sort]) ? params[:sort] : "name"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    @products = @products.order(@sort_column => @sort_direction)

    @pagy, @products = pagy(@products)

    # Load categories for filter dropdown
    @categories = current_organisation.categories.kept.sorted_by_full_path

    # Load last ERP product sync log (if ERP enabled)
    @last_product_sync = current_organisation.erp_sync_logs.for_entity('products').completed.recent.first if current_organisation.erp_configuration&.enabled?
  end

  def catalog_selection
    authorize Product, :generate_catalog?

    @categories = current_organisation.categories.kept.roots.order(:name)

    if params[:query].present?
      scope = current_organisation.products.includes(:categories, :product_variants)
      exact_ids = scope.left_joins(:categories, :product_variants).where(
        "unaccent(products.name) ILIKE unaccent(:q) OR unaccent(products.sku) ILIKE unaccent(:q) OR unaccent(categories.name) ILIKE unaccent(:q) OR unaccent(product_variants.sku) ILIKE unaccent(:q)",
        q: "%#{params[:query]}%"
      ).select("products.id").distinct
      fuzzy_ids = scope.left_joins(:categories).where(
        "similarity(unaccent(products.name), unaccent(:q)) > 0.3 OR similarity(unaccent(categories.name), unaccent(:q)) > 0.3",
        q: params[:query]
      ).select("products.id").distinct
      scope = scope.where(id: exact_ids).or(scope.where(id: fuzzy_ids)).order(:name)
      @pagy, @products = pagy(scope, items: 30)
      @search_mode = true
    else
      @search_mode = false
    end

    render partial: "catalog_selection_content", formats: [:html]
  end

  def generate_catalog
    authorize Product, :generate_catalog?

    product_ids = params[:product_ids]&.reject(&:blank?)
    category_ids = params[:catalog_category_ids]&.reject(&:blank?)

    options = {
      "catalog_title" => params[:catalog_title],
      "show_prices" => params[:show_prices],
      "show_sku" => params[:show_sku],
      "show_description" => params[:show_description],
      "show_variants" => params[:show_variants],
      "show_variant_sku" => params[:show_variant_sku],
      "show_variant_price" => params[:show_variant_price],
      "show_variant_photo" => params[:show_variant_photo],
      "catalog_layout" => params[:catalog_layout],
      "group_by_category" => params[:group_by_category],
      "client_name" => params[:client_name],
      "observations" => params[:observations],
      "only_available" => params[:only_available],
      "only_available_variants" => params[:only_available_variants],
      "sort_by" => params[:sort_by],
      "base_url" => request.base_url
    }

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "generate_catalog",
      status: :pending
    )

    GenerateCatalogJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      product_ids: product_ids,
      category_ids: category_ids,
      options: options
    )

    redirect_to bo_background_task_path(params[:org_slug], task)
  end

  def export_variants
    authorize Product, :export?

    task = current_organisation.background_tasks.create!(
      member: current_member,
      task_type: "export_product_variants",
      status: :pending
    )

    ExportJob.perform_later(
      task.id,
      organisation_id: current_organisation.id,
      export_class: "ProductVariant",
      export_type: "product_variants",
      columns: params[:columns],
      format: params[:format_type] || "csv",
      filter_params: filter_params_hash
    )

    redirect_to bo_background_task_path(params[:org_slug], task)
  end

  def show
  end

  def new
    @product = Product.new
    if params[:category_id].present?
      category = current_organisation.categories.kept.find_by(id: params[:category_id])
      @product.category_ids = [category.id] if category
    end
    authorize @product
  end

  def create
    @product = Product.new(product_params)
    @product.organisation = current_organisation
    authorize @product

    if @product.save
      save_product_attributes
      if current_organisation.deactivate_out_of_stock? && @product.default_variant
        StockRulesService.new(current_organisation).apply_to_variant(@product.default_variant)
      end
      redirect_to bo_product_path(params[:org_slug], @product), notice: "Product was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    update_params = product_params
    new_photos = update_params.delete(:photos)
    new_photos = nil if new_photos.blank? || new_photos == [""]

    if @product.update(update_params)
      @product.photos.attach(new_photos) if new_photos
      save_product_attributes
      redirect_to bo_product_path(params[:org_slug], @product, filter_params_hash), notice: "Product was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @product.destroy
      redirect_to bo_products_path(params[:org_slug], filter_params_hash), notice: "Product was successfully deleted."
    else
      redirect_to bo_product_path(params[:org_slug], @product, filter_params_hash), alert: @product.errors.full_messages.to_sentence
    end
  end

  def delete_photo
    photo = @product.photos.find(params[:photo_id])
    photo.purge
    redirect_to edit_bo_product_path(params[:org_slug], @product), notice: t('bo.flash.image_deleted')
  end

  def set_main_photo
    @product.update!(cover_photo_blob_id: params[:photo_id].to_i)
    redirect_to edit_bo_product_path(params[:org_slug], @product), notice: t('bo.flash.main_photo_set')
  end

  def configure_variants
    @available_attributes = current_organisation.product_attributes.kept.active.by_position.includes(:product_attribute_values)
  end

  def update_variant_configuration
    has_variants = params[:has_variants] == '1'
    attribute_ids = params.dig(:product, :product_attribute_ids)&.reject(&:blank?) || []
    available_value_ids = params.dig(:product, :available_attribute_value_ids)&.reject(&:blank?) || []

    ActiveRecord::Base.transaction do
      # Update has_variants flag
      @product.update!(has_variants: has_variants)

      # Update assigned attributes
      @product.product_product_attributes.destroy_all
      attribute_ids.each_with_index do |attr_id, index|
        @product.product_product_attributes.create!(product_attribute_id: attr_id, position: index + 1)
      end

      # Update available values
      @product.product_available_values.destroy_all
      available_value_ids.each do |value_id|
        @product.product_available_values.create!(product_attribute_value_id: value_id)
      end
    end

    redirect_to configure_variants_bo_product_path(params[:org_slug], @product), notice: t('bo.flash.variant_configuration_updated')
  rescue ActiveRecord::RecordInvalid => e
    @available_attributes = current_organisation.product_attributes.kept.active.by_position.includes(:product_attribute_values)
    flash.now[:alert] = e.message
    render :configure_variants, status: :unprocessable_entity
  end

  def related_products
    # Get related product IDs in order
    related_ids = @product.related_product_associations.order(:position).pluck(:related_product_id)

    # Fetch products and preserve order
    if related_ids.any?
      products_by_id = Product.where(id: related_ids).index_by(&:id)
      @selected_products = related_ids.map { |id| products_by_id[id] }.compact
    else
      @selected_products = []
    end

    @available_products = current_organisation.products
                                               .where.not(id: [@product.id] + related_ids)
                                               .where(published: true)
                                               .order(:name)
  end

  def update_related_products
    related_product_ids = params[:related_product_ids]&.reject(&:blank?) || []
    hide_related_products = params[:hide_related_products] == "1"

    ActiveRecord::Base.transaction do
      @product.update!(hide_related_products: hide_related_products)

      @product.related_product_associations.destroy_all
      related_product_ids.each_with_index do |product_id, index|
        @product.related_product_associations.create!(related_product_id: product_id, position: index + 1)
      end
    end

    redirect_to related_products_bo_product_path(params[:org_slug], @product), notice: t("bo.products.related.updated")
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = e.message
    redirect_to related_products_bo_product_path(params[:org_slug], @product)
  end

  def reorder_related_products
    positions = params[:positions] || []

    ActiveRecord::Base.transaction do
      positions.each_with_index do |product_id, index|
        association = @product.related_product_associations.find_by(related_product_id: product_id)
        association&.update!(position: index + 1)
      end
    end

    head :ok
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  helper_method :filter_params_hash, :sort_link_params, :storefront_state

  private

  def exportable_class
    Product
  end

  def exportable_base_scope
    policy_scope(current_organisation.products).includes(:categories)
  end

  def apply_export_filters(scope)
    apply_product_filters(scope)
  end

  def filter_params_hash
    { query: params[:query], category_id: params[:category_id], product_type: params[:product_type],
      price_status: params[:price_status], status: params[:status], storefront: params[:storefront],
      sort: params[:sort], direction: params[:direction] }.compact_blank
  end

  def sort_link_params(column)
    direction = (@sort_column == column && @sort_direction == "asc") ? "desc" : "asc"
    filter_params_hash.merge(sort: column, direction: direction)
  end

  def storefront_state(product)
    return "hidden" unless product.published?
    return "purchasable" if product.purchasable?
    # Published but not purchasable — check if any variant is visible
    variants = product.variable? ? product.product_variants.select { |v| !v.is_default? && v.published? } : product.product_variants.select(&:published?)
    has_visible = variants.any? { |v| v.available? || v.effective_stock_policy != 'hide' }
    has_visible ? "no_stock" : "hidden"
  end

  def apply_product_filters(scope)
    if params[:query].present?
      exact_ids = scope.left_joins(:categories, :product_variants).where(
        "unaccent(products.name) ILIKE unaccent(:q) OR unaccent(products.sku) ILIKE unaccent(:q) OR unaccent(products.description) ILIKE unaccent(:q) OR unaccent(categories.name) ILIKE unaccent(:q) OR unaccent(product_variants.sku) ILIKE unaccent(:q)",
        q: "%#{params[:query]}%"
      ).select("products.id").distinct
      fuzzy_ids = scope.left_joins(:categories).where(
        "similarity(unaccent(products.name), unaccent(:q)) > 0.3 OR similarity(unaccent(categories.name), unaccent(:q)) > 0.3",
        q: params[:query]
      ).select("products.id").distinct
      scope = scope.where(id: exact_ids).or(scope.where(id: fuzzy_ids))
    end

    if params[:category_id] == "none"
      product_ids_with_category = CategoryProduct.select(:product_id)
      scope = scope.where.not(id: product_ids_with_category)
    elsif params[:category_id].present?
      category = current_organisation.categories.kept.find_by(id: params[:category_id])
      if category
        @current_category = category
        all_category_ids = category.subtree_ids
        product_ids_in_category = CategoryProduct.where(category_id: all_category_ids).select(:product_id)
        scope = scope.where(id: product_ids_in_category)
      end
    end

    if params[:product_type].present?
      case params[:product_type]
      when "simple" then scope = scope.simple
      when "variable" then scope = scope.variable
      end
    end

    case params[:price_status]
    when "on_request" then scope = scope.where(price_on_request: true)
    when "zero_price" then scope = scope.where(price_on_request: false, unit_price: [nil, 0])
    when "has_price" then scope = scope.where(price_on_request: false).where("unit_price > 0")
    end

    case params[:status]
    when "published"
      scope = scope.where(published: true).where.not(
        id: Product.joins(:product_variants).where(has_variants: true, product_variants: { published: false }).select(:id)
      )
    when "unpublished"
      scope = scope.where(published: false)
    when "partial"
      scope = scope.where(has_variants: true, published: true).where(
        id: Product.joins(:product_variants).where(has_variants: true, product_variants: { published: false }).select(:id)
      )
    end

    if params[:storefront].present?
      # Compute storefront state in Ruby (depends on effective_stock_policy which resolves inherit)
      all_products = scope.includes(:product_variants).to_a
      filtered_ids = all_products.select { |p| storefront_state(p) == params[:storefront] }.map(&:id)
      scope = scope.where(id: filtered_ids)
    end

    scope
  end

  def set_product
    @product = current_organisation.products.includes(:product_variants).find(params[:id])
    authorize @product
  end

  def product_params
    params.require(:product).permit(:name, :slug, :sku, :description, :price, :unit_description, :min_quantity, :min_quantity_type, :published, :price_on_request, :category_id, category_ids: [], photos: [])
  end

  def parse_uploaded_file(uploaded_file)
    filename = uploaded_file.original_filename.downcase

    if filename.end_with?(".xlsx", ".xls")
      convert_excel_to_csv(uploaded_file)
    else
      content = uploaded_file.read.force_encoding("UTF-8")
      content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end

  def convert_excel_to_csv(uploaded_file)
    spreadsheet = Roo::Spreadsheet.open(uploaded_file.path || uploaded_file.tempfile.path)
    sheet = spreadsheet.sheet(0)

    CSV.generate do |csv|
      sheet.each_row_streaming(pad_cells: true) do |row|
        csv << row.map { |cell| cell&.value.to_s }
      end
    end
  end

  def detect_csv_delimiter(content)
    sample = content[0, 1024] || content
    first_line = sample.lines.first || ""
    semicolons = first_line.count(";")
    commas = first_line.count(",")
    tabs = first_line.count("\t")

    if semicolons > commas && semicolons > tabs
      ";"
    elsif tabs > commas && tabs > semicolons
      "\t"
    else
      ","
    end
  end

  def load_attributes_for_form
    @all_attributes = {}
    @current_attribute_value_ids = []

    current_organisation.product_attributes.kept.active.by_position.each do |attribute|
      values = attribute.product_attribute_values.where(active: true).naturally_sorted
      @all_attributes[attribute] = values
    end

    if @product&.persisted? && !@product.has_variants?
      @current_attribute_value_ids = @product.default_variant&.attribute_values&.pluck(:id) || []
    end
  end

  def save_product_attributes
    return if @product.has_variants?

    variant = @product.default_variant
    return unless variant

    ids = params.dig(:product, :attribute_value_ids)&.reject(&:blank?)&.map(&:to_i) || []

    variant.variant_attribute_values.destroy_all
    ids.each do |value_id|
      variant.variant_attribute_values.create!(product_attribute_value_id: value_id)
    end

    sync_product_attribute_associations(ids)
  end

  def sync_product_attribute_associations(value_ids)
    if value_ids.blank?
      @product.product_product_attributes.destroy_all
      @product.product_available_values.destroy_all
      return
    end

    values = ProductAttributeValue.where(id: value_ids)
    attribute_ids = values.pluck(:product_attribute_id).uniq

    @product.product_product_attributes.where.not(product_attribute_id: attribute_ids).destroy_all
    attribute_ids.each_with_index do |attr_id, index|
      @product.product_product_attributes.find_or_create_by!(product_attribute_id: attr_id) do |ppa|
        ppa.position = index + 1
      end
    end

    @product.product_available_values.where.not(product_attribute_value_id: value_ids).destroy_all
    value_ids.each do |val_id|
      @product.product_available_values.find_or_create_by!(product_attribute_value_id: val_id)
    end
  end
end
