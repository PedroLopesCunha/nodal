# frozen_string_literal: true

require "csv"

namespace :sync do
  desc "Sync products from a cleaned WordPress CSV export"
  task :from_cleaned_csv, [:csv_path, :org_slug, :mode] => :environment do |_t, args|
    csv_path = args[:csv_path]
    org_slug = args[:org_slug]
    mode     = args[:mode] || "dry_run"

    unless csv_path && org_slug
      puts "Usage:"
      puts "  rails 'sync:from_cleaned_csv[path/to/file.csv,org-slug,dry_run]'  # preview changes"
      puts "  rails 'sync:from_cleaned_csv[path/to/file.csv,org-slug,execute]'  # apply changes"
      exit 1
    end

    unless %w[dry_run execute].include?(mode)
      puts "Error: mode must be 'dry_run' or 'execute', got '#{mode}'"
      exit 1
    end

    unless File.exist?(csv_path)
      puts "Error: CSV file not found at #{csv_path}"
      exit 1
    end

    org = Organisation.find_by(slug: org_slug)
    unless org
      puts "Error: Organisation '#{org_slug}' not found"
      exit 1
    end

    # ── Helper lambdas ─────────────────────────────────────────────────

    parse_price = ->(value) {
      return nil if value.blank?

      cleaned = value.to_s.gsub(/[^\d.,\-]/, "")

      # Handle European format (comma as decimal)
      if cleaned.include?(".") && cleaned.include?(",")
        if cleaned.rindex(",") > cleaned.rindex(".")
          cleaned = cleaned.gsub(".", "").gsub(",", ".")
        else
          cleaned = cleaned.gsub(",", "")
        end
      elsif cleaned.include?(",")
        cleaned = cleaned.gsub(",", ".")
      end

      (cleaned.to_f * 100).round
    }

    normalize_value = ->(attr_name, value) {
      val = value.strip

      case attr_name
      when "Espessura"
        val = val.gsub(/(\d+),\s*cm/, '\1 cm')
      when "Tamanho"
        val = val.gsub(/(\d)x(\d)/, '\1 x \2')
        val = val.gsub(/\b0+(\d+)/, '\1')
        val = val.gsub(/\s+-/, '-')
        val = val.gsub(/,cm/, 'cm')
        val = val.gsub(/Alt\.(\d)/, 'Alt. \1')
        val = val.sub(/\bbase\b/, 'Base')
      end

      val
    }

    extract_variation_attrs = ->(row) {
      attrs = {}
      4.times do |i|
        attr_name = row["Atributo #{i + 1} nome"]&.strip
        attr_value = row["Atributo #{i + 1} valor(es)"]&.strip
        next if attr_name.blank? || attr_value.blank?
        attrs[attr_name] = normalize_value.call(attr_name, attr_value)
      end
      attrs
    }

    # ── Main logic ─────────────────────────────────────────────────────

    dry_run = mode == "dry_run"
    puts "=" * 70
    puts dry_run ? "DRY RUN — no changes will be made" : "EXECUTE MODE — changes will be applied"
    puts "Organisation: #{org.name} (#{org.slug})"
    puts "=" * 70

    # ── Phase 1: Parse CSV ─────────────────────────────────────────────
    puts "\n[Phase 1] Parsing CSV...\n"

    csv_products = {}      # SKU => row data for simple/variable products
    csv_variations = {}    # Parent SKU => [variation rows]
    rows = CSV.read(csv_path, headers: true, liberal_parsing: true)

    rows.each do |row|
      tipo = row["Tipo"]&.strip
      next unless %w[simple variable variation].include?(tipo)

      if tipo == "variation"
        parent_sku = row["Pai"]&.strip
        next if parent_sku.blank?
        csv_variations[parent_sku] ||= []
        csv_variations[parent_sku] << row
      else
        sku = row["REF"]&.strip
        next if sku.blank?
        csv_products[sku] = row
      end
    end

    simple_count = csv_products.values.count { |r| r["Tipo"] == "simple" }
    variable_count = csv_products.values.count { |r| r["Tipo"] == "variable" }
    variation_count = csv_variations.values.sum(&:size)

    puts "  Products in CSV: #{csv_products.size} (#{simple_count} simple, #{variable_count} variable)"
    puts "  Variations in CSV: #{variation_count}"

    # ── Phase 2: Compare with DB ───────────────────────────────────────
    puts "\n[Phase 2] Comparing with database...\n"

    db_products = org.products.includes(product_variants: { attribute_values: :product_attribute }).index_by(&:sku)
    puts "  Products in DB: #{db_products.size}"

    # Track changes
    changes = {
      product_updates: [],      # { product, field, old, new }
      variant_updates: [],      # { variant, field, old, new }
      variants_to_delete: [],   # variants in DB but not in CSV
      not_found_in_db: [],      # SKUs in CSV but not in DB
      orphan_variations: []     # variations whose parent doesn't exist
    }

    # 2a. Check products
    csv_products.each do |sku, row|
      product = db_products[sku]
      unless product
        changes[:not_found_in_db] << sku
        next
      end

      # Check name change
      csv_name = row["Nome"]&.strip
      if csv_name.present? && product.name != csv_name
        changes[:product_updates] << {
          product: product,
          field: :name,
          old: product.name,
          new: csv_name
        }
      end

      # Check description change
      csv_desc = row["Descrição breve"]&.strip
      if csv_desc.present? && product.description != csv_desc
        changes[:product_updates] << {
          product: product,
          field: :description,
          old: product.description,
          new: csv_desc
        }
      end

      # Check has_variants change (type)
      csv_has_variants = row["Tipo"] == "variable"
      if product.has_variants? != csv_has_variants
        changes[:product_updates] << {
          product: product,
          field: :has_variants,
          old: product.has_variants?,
          new: csv_has_variants
        }
      end

      # Check price for simple products
      if row["Tipo"] == "simple"
        csv_price = parse_price.call(row["Preço normal"])
        if csv_price && product.unit_price != csv_price
          changes[:product_updates] << {
            product: product,
            field: :unit_price,
            old: product.unit_price,
            new: csv_price
          }
        end
      end
    end

    # 2b. Check variations
    csv_variations.each do |parent_sku, variations|
      parent_product = db_products[parent_sku]
      unless parent_product
        changes[:orphan_variations] << { parent_sku: parent_sku, count: variations.size }
        next
      end

      # Build a map of CSV variations by attribute combination
      csv_var_by_attrs = {}
      variations.each do |row|
        attrs = extract_variation_attrs.call(row)
        key = attrs.sort.map { |k, v| "#{k}:#{v}" }.join("|")
        csv_var_by_attrs[key] = row
      end

      # Check each DB variant
      parent_product.product_variants.each do |db_variant|
        next if db_variant.is_default?

        # Build key from DB variant's attributes
        db_attrs = db_variant.attribute_values.map do |av|
          [av.product_attribute.name, av.value]
        end.to_h
        db_key = db_attrs.sort.map { |k, v| "#{k}:#{v}" }.join("|")

        csv_row = csv_var_by_attrs[db_key]

        if csv_row
          # Variant exists in CSV - check for updates
          csv_var_name = csv_row["Nome"]&.strip
          csv_var_sku = csv_row["REF"]&.strip
          csv_var_price = parse_price.call(csv_row["Preço normal"])

          if csv_var_name.present? && db_variant.name != csv_var_name
            changes[:variant_updates] << {
              variant: db_variant,
              field: :name,
              old: db_variant.name,
              new: csv_var_name
            }
          end

          if csv_var_sku.present? && db_variant.sku != csv_var_sku
            changes[:variant_updates] << {
              variant: db_variant,
              field: :sku,
              old: db_variant.sku,
              new: csv_var_sku
            }
          end

          if csv_var_price && db_variant.unit_price_cents != csv_var_price
            changes[:variant_updates] << {
              variant: db_variant,
              field: :unit_price_cents,
              old: db_variant.unit_price_cents,
              new: csv_var_price
            }
          end

          # Remove from map so we can track what's left
          csv_var_by_attrs.delete(db_key)
        else
          # Variant in DB but not in CSV - mark for deletion
          changes[:variants_to_delete] << db_variant
        end
      end
    end

    # Also check for variants of products that became simple
    csv_products.each do |sku, row|
      next unless row["Tipo"] == "simple"
      product = db_products[sku]
      next unless product

      # If product was variable (has non-default variants), those should be deleted
      product.product_variants.each do |variant|
        next if variant.is_default?
        changes[:variants_to_delete] << variant unless changes[:variants_to_delete].include?(variant)
      end
    end

    # ── Phase 2b: Show changes ─────────────────────────────────────────
    puts "\n  SUMMARY OF CHANGES:"

    # Group product updates by field
    product_updates_by_field = changes[:product_updates].group_by { |c| c[:field] }
    puts "\n  PRODUCT UPDATES (#{changes[:product_updates].size} total):"
    product_updates_by_field.each do |field, updates|
      puts "    #{field}: #{updates.size} products"
      if dry_run && updates.size <= 10
        updates.each do |u|
          puts "      - #{u[:product].sku}: '#{u[:old]}' → '#{u[:new]}'"
        end
      elsif dry_run
        updates.first(5).each do |u|
          puts "      - #{u[:product].sku}: '#{u[:old]}' → '#{u[:new]}'"
        end
        puts "      ... and #{updates.size - 5} more"
      end
    end

    # Variant updates
    variant_updates_by_field = changes[:variant_updates].group_by { |c| c[:field] }
    puts "\n  VARIANT UPDATES (#{changes[:variant_updates].size} total):"
    variant_updates_by_field.each do |field, updates|
      puts "    #{field}: #{updates.size} variants"
      if dry_run && updates.size <= 10
        updates.each do |u|
          puts "      - #{u[:variant].product.sku}/#{u[:variant].name}: '#{u[:old]}' → '#{u[:new]}'"
        end
      elsif dry_run
        updates.first(5).each do |u|
          puts "      - #{u[:variant].product.sku}/#{u[:variant].name}: '#{u[:old]}' → '#{u[:new]}'"
        end
        puts "      ... and #{updates.size - 5} more"
      end
    end

    # Variants to delete
    puts "\n  VARIANTS TO DELETE: #{changes[:variants_to_delete].size}"
    if dry_run && changes[:variants_to_delete].any?
      changes[:variants_to_delete].first(10).each do |v|
        puts "    - #{v.product.sku} / #{v.name} (#{v.option_values_string})"
      end
      if changes[:variants_to_delete].size > 10
        puts "    ... and #{changes[:variants_to_delete].size - 10} more"
      end
    end

    # Not found in DB
    if changes[:not_found_in_db].any?
      puts "\n  NOT FOUND IN DB (#{changes[:not_found_in_db].size}):"
      changes[:not_found_in_db].first(10).each { |sku| puts "    - #{sku}" }
      if changes[:not_found_in_db].size > 10
        puts "    ... and #{changes[:not_found_in_db].size - 10} more"
      end
    end

    # Orphan variations
    if changes[:orphan_variations].any?
      puts "\n  ORPHAN VARIATIONS (parent not in DB):"
      changes[:orphan_variations].each do |ov|
        puts "    - #{ov[:parent_sku]}: #{ov[:count]} variations"
      end
    end

    if dry_run
      puts "\n" + "=" * 70
      puts "DRY RUN complete. Run with 'execute' to apply changes."
      puts "=" * 70
      next
    end

    # ── Phase 3: Execute changes ───────────────────────────────────────
    puts "\n[Phase 3] Executing changes...\n"

    stats = {
      products_updated: 0,
      variants_updated: 0,
      variants_deleted: 0,
      errors: []
    }

    ActiveRecord::Base.transaction do
      # 3a. Update products
      puts "\n  Updating products..."
      changes[:product_updates].group_by { |c| c[:product] }.each do |product, updates|
        attrs = {}
        updates.each { |u| attrs[u[:field]] = u[:new] }

        begin
          product.update!(attrs)
          stats[:products_updated] += 1
        rescue => e
          stats[:errors] << "Product #{product.sku}: #{e.message}"
        end
      end

      # 3b. Update variants
      puts "  Updating variants..."
      changes[:variant_updates].group_by { |c| c[:variant] }.each do |variant, updates|
        attrs = {}
        updates.each { |u| attrs[u[:field]] = u[:new] }

        begin
          variant.update!(attrs)
          stats[:variants_updated] += 1
        rescue => e
          stats[:errors] << "Variant #{variant.product.sku}/#{variant.name}: #{e.message}"
        end
      end

      # 3c. Delete orphan variants
      puts "  Deleting orphan variants..."
      changes[:variants_to_delete].each do |variant|
        begin
          # Check if variant has any order items
          if variant.order_items.any?
            puts "    SKIP: #{variant.product.sku}/#{variant.name} has order items"
            stats[:errors] << "Cannot delete variant #{variant.name} - has order items"
          else
            variant.destroy!
            stats[:variants_deleted] += 1
          end
        rescue => e
          stats[:errors] << "Delete variant #{variant.name}: #{e.message}"
        end
      end
    end

    # ── Summary ────────────────────────────────────────────────────────
    puts "\n" + "=" * 70
    puts "Sync complete!"
    puts "  Products updated:  #{stats[:products_updated]}"
    puts "  Variants updated:  #{stats[:variants_updated]}"
    puts "  Variants deleted:  #{stats[:variants_deleted]}"
    puts "  Errors:            #{stats[:errors].size}"

    if stats[:errors].any?
      puts "\nErrors:"
      stats[:errors].first(20).each { |e| puts "  - #{e}" }
      if stats[:errors].size > 20
        puts "  ... and #{stats[:errors].size - 20} more"
      end
    end

    puts "=" * 70
  end
end
