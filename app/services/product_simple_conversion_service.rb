class ProductSimpleConversionService
  def initialize(product, variant_id: nil)
    @product = product
    @variant_id = variant_id
  end

  def call
    @product.with_lock do
      variants = @product.product_variants.where(is_default: false)
      variant = if @variant_id.present?
        variants.find_by(id: @variant_id)
      elsif variants.count == 1
        variants.first
      end
      unless variant
        @product.errors.add(:base, I18n.t("bo.products.configure_variants.choose_simple_variant", default: "Escolhe a variante que queres manter como produto simples."))
        raise ActiveRecord::RecordInvalid, @product
      end

      internal_base = @product.product_variants.where(is_default: true).first
      @product.product_variants.where(is_default: true).update_all(is_default: false)
      variant.update_column(:is_default, true)
      @product.product_variants.reset
      @product.update!(has_variants: false, unit_price: variant.unit_price_cents, sku: variant.sku,
                       published: variant.published, available: variant.available,
                       variable_base_variant_id: internal_base&.id)

      value_ids = variant.attribute_values.ids
      attribute_ids = variant.attribute_values.pluck(:product_attribute_id).uniq
      @product.product_product_attributes.where.not(product_attribute_id: attribute_ids).destroy_all
      attribute_ids.each do |id|
        @product.product_product_attributes.find_or_create_by!(product_attribute_id: id)
      end
      @product.product_available_values.where.not(product_attribute_value_id: value_ids).destroy_all
      value_ids.each do |id|
        @product.product_available_values.find_or_create_by!(product_attribute_value_id: id)
      end

      if variant.photo.attached?
        @product.photos.attach(variant.photo.blob) unless @product.photos.exists?(blob_id: variant.photo.blob_id)
        @product.update!(cover_photo_blob_id: variant.photo.blob_id)
      end
      variant
    end
  end
end
