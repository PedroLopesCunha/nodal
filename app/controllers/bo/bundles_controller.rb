class Bo::BundlesController < Bo::BaseController
  before_action :load_bundle, only: [:show, :edit, :update, :destroy, :sync_erp]

  def show
    @product = @bundle
    @summary = composition_summary(@bundle.bundle_components.map { |part| { product_variant_id: part.product_variant_id, quantity: part.quantity } }, @bundle.unit_price)
  end

  def sync_erp
    authorize @bundle, :sync_erp?
    unless erp_product_sync_enabled?
      respond_to do |format|
        format.json { render json: { error: t("bo.products.erp_sync.unavailable") }, status: :unprocessable_entity }
        format.html { redirect_to bo_bundle_path(params[:org_slug], @bundle), alert: t("bo.products.erp_sync.unavailable") }
      end
      return
    end
    task = current_organisation.background_tasks.create!(member: current_member,
      task_type: "erp_product_sync", result: { product_id: @bundle.id, bundle_id: @bundle.id })
    ErpBundleSyncJob.perform_later(task.id, product_id: @bundle.id)
    respond_to do |format|
      format.json { render json: { status_url: bo_background_task_path(params[:org_slug], task, format: :json) }, status: :accepted }
      format.html { redirect_to bo_bundle_path(params[:org_slug], @bundle), notice: t("bo.products.erp_sync.queued") }
    end
  end

  def index
    @bundles = policy_scope(current_organisation.products).bundles.order(:bundle_position, :name)
    authorize current_organisation.products.new, :create?
    if params[:query].present?
      @bundles = @bundles.where("name ILIKE ?", "%#{Product.sanitize_sql_like(params[:query].to_s.strip)}%")
    end
    @bundles = @bundles.where(published: params[:status] == "published") if params[:status].in?(%w[published unpublished])
    @pagy, @bundles = pagy(@bundles.includes(:photos_attachments, :bundle_components))
  end

  def new
    @bundle = current_organisation.products.new(bundle: true, published: false)
    authorize @bundle, :create?
    2.times { @bundle.bundle_components.build }
    load_categories
  end

  def create
    @bundle = current_organisation.products.new(bundle_params.merge(bundle: true))
    authorize @bundle, :create?
    if @bundle.save
      redirect_to bo_bundle_path(params[:org_slug], @bundle), notice: t("bundles.saved")
    else
      load_categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_categories
  end

  def update
    attributes = bundle_params
    photos = attributes.delete(:photos).reject(&:blank?) if attributes[:photos]
    if @bundle.update(attributes)
      @bundle.photos.attach(photos) if photos.present?
      redirect_to bo_bundle_path(params[:org_slug], @bundle), notice: t("bundles.saved")
    else
      load_categories
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @bundle.destroy
      redirect_to bo_bundles_path(params[:org_slug]), notice: t("bundles.removed")
    else
      redirect_to edit_bo_bundle_path(params[:org_slug], @bundle), alert: @bundle.errors.full_messages.to_sentence
    end
  end

  def components
    authorize current_organisation.products.new, :create?
    scope = current_organisation.product_variants.joins(:product).where(products: { bundle: false })
      .where("NOT (products.has_variants AND product_variants.is_default)")
    term = params[:query].presence || params[:q]
    if term.present?
      query = "%#{Product.sanitize_sql_like(term.to_s)}%"
      scope = scope.where("products.name ILIKE :q OR product_variants.sku ILIKE :q", q: query)
    end
    render json: scope.includes(:product).order(:sku, :id).limit(30).map { |v|
      { id: v.id, label: v.picker_label, value: v.id,
        text: [v.product.name, v.option_values_string].compact_blank.join(" · "), sku: v.sku }
    }
  end

  def preview
    authorize current_organisation.products.new, :create?
    parts = params.permit(components: [:product_variant_id, :quantity]).fetch(:components, [])
    raw_price = params[:price].to_s.strip
    price = raw_price.match?(/\A\d+(?:[.,]\d{0,2})?\z/) ? current_organisation.products.new(price: raw_price).unit_price : nil
    render json: composition_summary(parts, price)
  rescue BundleCompositionSummary::InvalidComposition => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def load_bundle
    @bundle = current_organisation.products.bundles.find(params[:id])
    permission = { "show" => :show?, "destroy" => :destroy?, "sync_erp" => :sync_erp? }.fetch(action_name, :update?)
    authorize @bundle, permission
  end

  def load_categories
    @categories = current_organisation.categories.kept.sorted_by_full_path
    @summary = composition_summary(@bundle.bundle_components.reject(&:marked_for_destruction?).map { |part| { product_variant_id: part.product_variant_id, quantity: part.quantity } }, @bundle.unit_price)
  rescue BundleCompositionSummary::InvalidComposition
    @summary = nil
  end

  def composition_summary(parts, price)
    BundleCompositionSummary.new(organisation: current_organisation, components: parts, price_cents: price).call
  end

  def bundle_params
    values = params.require(:product).permit(:name, :slug, :unit_description, :description, :rich_description, :price, :published, :bundle_featured,
      :bundle_position, :quick_add_enabled, photos: [], category_ids: [], bundle_components_attributes: [:id, :product_variant_id, :quantity, :_destroy])
    ids = values.fetch(:bundle_components_attributes, {}).values.filter_map { |v| v[:product_variant_id].presence }.map(&:to_s).uniq
    allowed = current_organisation.product_variants.where(id: ids).pluck(:id).map(&:to_s)
    raise ActiveRecord::RecordNotFound if (ids - allowed).any?
    if values[:category_ids]
      valid_ids = current_organisation.categories.kept.where(id: values[:category_ids].reject(&:blank?)).pluck(:id)
      values[:category_ids] = valid_ids
    end
    values
  end
end
