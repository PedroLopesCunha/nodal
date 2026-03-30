class Bo::HomepageSettingsController < Bo::BaseController
  before_action :set_and_authorize_organisation

  def edit
    load_data
  end

  def update
    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.flash.settings_updated')
  end

  # Banners
  def create_banner
    banner = @organisation.homepage_banners.build(banner_params)
    if banner.save
      redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.banner_created')
    else
      load_data
      flash.now[:alert] = banner.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def update_banner
    banner = @organisation.homepage_banners.find(params[:banner_id])
    if banner.update(banner_params)
      redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.banner_updated')
    else
      load_data
      flash.now[:alert] = banner.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle_banner
    banner = @organisation.homepage_banners.find(params[:banner_id])
    banner.update!(active: !banner.active?)
    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug)
  end

  def destroy_banner
    banner = @organisation.homepage_banners.find(params[:banner_id])
    banner.destroy
    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.banner_deleted')
  end

  # Featured Products
  def add_featured_products
    product_ids = params[:product_ids] || []
    products = @organisation.products.where(id: product_ids)

    products.each do |product|
      @organisation.homepage_featured_products.find_or_create_by(product: product)
    end

    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.products_added', count: products.count)
  end

  def remove_featured_product
    @organisation.homepage_featured_products.find_by(product_id: params[:product_id])&.destroy
    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.product_removed')
  end

  # Featured Categories
  def add_featured_categories
    category_ids = params[:category_ids] || []
    categories = @organisation.categories.kept.where(id: category_ids)

    categories.each do |category|
      @organisation.homepage_featured_categories.find_or_create_by(category: category)
    end

    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.categories_added', count: categories.count)
  end

  def remove_featured_category
    @organisation.homepage_featured_categories.find_by(category_id: params[:category_id])&.destroy
    redirect_to edit_bo_homepage_settings_path(org_slug: @organisation.slug), notice: t('bo.homepage_settings.flash.category_removed')
  end

  private

  def set_and_authorize_organisation
    @organisation = current_organisation
    authorize @organisation, :update?, policy_class: SettingPolicy
  end

  def load_data
    @banners = @organisation.homepage_banners.by_position.includes(image_attachment: :blob)
    @featured_products = @organisation.homepage_featured_products.order(:position).includes(product: { photos_attachments: :blob })
    @featured_categories = @organisation.homepage_featured_categories.order(:position).includes(:category)
  end

  def banner_params
    params.require(:homepage_banner).permit(:image, :title, :subtitle, :link_url, :link_text, :active, :text_theme)
  end
end
