namespace :data do
  desc "Normalize product/variant data: variant becomes source of truth for SKU, external_id, price, stock"
  task :normalize_variants, [:org_slug, :mode] => :environment do |_t, args|
    org_slug = args[:org_slug]
    mode = args[:mode] || 'dry_run'

    abort "Usage: bin/rails 'data:normalize_variants[org_slug,dry_run|execute]'" unless org_slug.present?

    org = Organisation.find_by!(slug: org_slug)
    dry_run = mode != 'execute'

    puts dry_run ? "=== DRY RUN ===" : "=== EXECUTING ==="
    puts "Organisation: #{org.name} (#{org.slug})"
    puts ""

    stats = { simple_fixed: 0, variable_fixed: 0, ext_id_moved: 0, ext_id_bootstrapped: 0, errors: [] }

    # === SIMPLE PRODUCTS ===
    puts "--- Simple Products (has_variants: false) ---"
    org.products.simple.find_each do |product|
      variant = product.default_variant
      next unless variant

      changes = []

      # Move external_id from product to variant if variant doesn't have one
      if product.external_id.present? && variant.external_id.blank?
        changes << "  external_id: product(#{product.external_id}) → variant"
        unless dry_run
          variant.update_columns(
            external_id: product.external_id,
            external_source: product.external_source,
            last_synced_at: product.last_synced_at
          )
        end
        stats[:ext_id_moved] += 1
      end

      # If variant has external_id but product still has one, clear product's
      if product.external_id.present?
        changes << "  clear product.external_id (#{product.external_id})"
        unless dry_run
          product.update_columns(external_id: nil, external_source: nil, last_synced_at: nil, sync_error: nil)
        end
      end

      # Ensure SKUs match (variant wins on mismatch)
      if variant.sku.present? && product.sku != variant.sku
        changes << "  product.sku: '#{product.sku}' → '#{variant.sku}' (mirror from variant)"
        product.update_columns(sku: variant.sku) unless dry_run
        stats[:simple_fixed] += 1
      elsif variant.sku.blank? && product.sku.present?
        changes << "  variant.sku: nil → '#{product.sku}' (copy from product)"
        variant.update_columns(sku: product.sku) unless dry_run
        stats[:simple_fixed] += 1
      end

      # Bootstrap external_id = sku if variant has SKU but no external_id
      if variant.sku.present? && variant.external_id.blank?
        # Reload to get any updates from above
        ext_id = variant.reload.external_id
        if ext_id.blank?
          changes << "  bootstrap variant.external_id = '#{variant.sku}'"
          variant.update_columns(external_id: variant.sku) unless dry_run
          stats[:ext_id_bootstrapped] += 1
        end
      end

      if changes.any?
        puts "Product ##{product.id} '#{product.name}' (SKU: #{product.sku})"
        changes.each { |c| puts c }
      end
    rescue => e
      stats[:errors] << "Product ##{product.id}: #{e.message}"
    end

    puts ""

    # === VARIABLE PRODUCTS ===
    puts "--- Variable Products (has_variants: true) ---"
    org.products.variable.find_each do |product|
      variant = product.default_variant
      next unless variant

      changes = []

      # Clear default variant's SKU, external_id, price, stock
      if variant.sku.present?
        changes << "  default variant: clear sku '#{variant.sku}'"
      end
      if variant.external_id.present?
        changes << "  default variant: clear external_id '#{variant.external_id}'"
      end
      if variant.unit_price_cents.present? && variant.unit_price_cents > 0
        changes << "  default variant: clear unit_price_cents (#{variant.unit_price_cents})"
      end
      if variant.stock_quantity.to_i > 0
        changes << "  default variant: clear stock_quantity (#{variant.stock_quantity})"
      end
      if variant.track_stock?
        changes << "  default variant: set track_stock = false"
      end

      unless dry_run
        variant.update_columns(
          sku: nil,
          external_id: nil,
          external_source: nil,
          last_synced_at: nil,
          sync_error: nil,
          unit_price_cents: nil,
          stock_quantity: 0,
          track_stock: false
        )
      end

      # Clear product-level external_id and price
      product_changes = []
      if product.external_id.present?
        product_changes << "  product: clear external_id '#{product.external_id}'"
      end
      if product.unit_price.present? && product.unit_price > 0
        product_changes << "  product: clear unit_price (#{product.unit_price})"
      end

      unless dry_run
        product.update_columns(
          external_id: nil,
          external_source: nil,
          last_synced_at: nil,
          sync_error: nil,
          unit_price: nil
        )
      end

      # Bootstrap external_id = sku for non-default variants
      product.product_variants.where(is_default: false).where.not(sku: [nil, '']).find_each do |v|
        if v.external_id.blank?
          changes << "  variant '#{v.name}' (SKU: #{v.sku}): bootstrap external_id = '#{v.sku}'"
          v.update_columns(external_id: v.sku) unless dry_run
          stats[:ext_id_bootstrapped] += 1
        end
      end

      all_changes = changes + product_changes
      if all_changes.any?
        puts "Product ##{product.id} '#{product.name}' (SKU: #{product.sku})"
        all_changes.each { |c| puts c }
        stats[:variable_fixed] += 1
      end
    rescue => e
      stats[:errors] << "Product ##{product.id}: #{e.message}"
    end

    puts ""
    puts "=== Summary ==="
    puts "Simple products fixed: #{stats[:simple_fixed]}"
    puts "Variable products fixed: #{stats[:variable_fixed]}"
    puts "External IDs moved product→variant: #{stats[:ext_id_moved]}"
    puts "External IDs bootstrapped (=sku): #{stats[:ext_id_bootstrapped]}"
    puts "Errors: #{stats[:errors].count}"
    stats[:errors].each { |e| puts "  #{e}" }
    puts ""
    puts dry_run ? "DRY RUN complete. Run with 'execute' to apply changes." : "DONE. Changes applied."
  end
end
