# frozen_string_literal: true

require "csv"

namespace :cleanup do
  desc "Clean up imported WordPress attributes using a corrected CSV"
  task :attributes, [:csv_path, :org_slug, :mode] => :environment do |_t, args|
    csv_path = args[:csv_path]
    org_slug = args[:org_slug]
    mode     = args[:mode] || "dry_run"

    unless csv_path && org_slug
      puts "Usage:"
      puts "  rails 'cleanup:attributes[path/to/file.csv,org-slug,dry_run]'  # preview changes"
      puts "  rails 'cleanup:attributes[path/to/file.csv,org-slug,execute]'  # apply changes"
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

    dry_run = mode == "dry_run"
    puts "=" * 70
    puts dry_run ? "DRY RUN — no changes will be made" : "EXECUTE MODE — changes will be applied"
    puts "Organisation: #{org.name} (#{org.slug})"
    puts "=" * 70

    # ── Phase 1: Parse CSV & normalize ──────────────────────────────────

    puts "\n[Phase 1] Parsing CSV and normalizing attribute values...\n\n"

    # Desired attribute names from CSV → normalized values
    # Key: attribute name (as it should appear), Value: Set of normalized values
    csv_attributes = Hash.new { |h, k| h[k] = Set.new }

    # Per-product attribute mapping: { product_sku => { attr_name => Set[values] } }
    product_attr_map = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Set.new } }

    # Per-variant mapping: { parent_sku => { variant_name => { attr_name => value } } }
    variant_attr_map = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }

    # Track ambiguous variant names: { parent_sku => { variant_name => count } }
    variant_name_counts = Hash.new { |h, k| h[k] = Hash.new(0) }

    rows = CSV.read(csv_path, headers: true, liberal_parsing: true)

    # First pass: count variant names per parent to detect ambiguity
    rows.each do |row|
      next unless row["Tipo"] == "variation"
      parent_sku = row["Pai"]&.strip
      var_name   = row["Nome"]&.strip
      next if parent_sku.blank? || var_name.blank?
      variant_name_counts[parent_sku][var_name] += 1
    end

    # Second pass: build the maps
    rows.each do |row|
      tipo = row["Tipo"]&.strip
      next unless %w[variable variation].include?(tipo)

      if tipo == "variable"
        sku = row["REF"]&.strip
        next if sku.blank?

        4.times do |i|
          attr_name  = row["Atributo #{i + 1} nome"]&.strip
          values_str = row["Atributo #{i + 1} valor(es)"]&.strip
          next if attr_name.blank? || values_str.blank?

          values_str.split(",").map(&:strip).reject(&:blank?).each do |val|
            normalized = normalize_value(attr_name, val)
            csv_attributes[attr_name].add(normalized)
            product_attr_map[sku][attr_name].add(normalized)
          end
        end

      elsif tipo == "variation"
        parent_sku = row["Pai"]&.strip
        var_name   = row["Nome"]&.strip
        next if parent_sku.blank? || var_name.blank?

        4.times do |i|
          attr_name  = row["Atributo #{i + 1} nome"]&.strip
          value_str  = row["Atributo #{i + 1} valor(es)"]&.strip
          next if attr_name.blank? || value_str.blank?

          normalized = normalize_value(attr_name, value_str.strip)
          variant_attr_map[parent_sku][var_name][attr_name] = normalized
        end
      end
    end

    csv_attr_names = csv_attributes.keys.to_set
    total_values = csv_attributes.values.sum(&:size)

    puts "  CSV attributes (#{csv_attr_names.size}): #{csv_attr_names.to_a.sort.join(', ')}"
    csv_attributes.sort_by { |k, _| k }.each do |attr_name, values|
      puts "    #{attr_name} (#{values.size} values): #{values.to_a.sort.join(', ')}"
    end
    puts "  Products with attributes: #{product_attr_map.size}"
    puts "  Variants to link: #{variant_attr_map.values.sum { |h| h.size }}"

    # Report ambiguous variant names
    ambiguous = []
    variant_name_counts.each do |parent_sku, names|
      names.each do |name, count|
        ambiguous << { parent_sku: parent_sku, name: name, count: count } if count > 1
      end
    end

    if ambiguous.any?
      puts "\n  ⚠ AMBIGUOUS variant names (#{ambiguous.size} — will be SKIPPED):"
      ambiguous.each do |a|
        puts "    Parent #{a[:parent_sku]}: '#{a[:name]}' appears #{a[:count]} times"
      end
    end

    # ── Phase 2: Compare with DB ────────────────────────────────────────

    puts "\n[Phase 2] Comparing with current DB state...\n\n"

    db_attrs = org.product_attributes.includes(:product_attribute_values).index_by(&:name)
    db_attr_names = db_attrs.keys.to_set

    attrs_to_delete = db_attr_names - csv_attr_names
    attrs_to_create = csv_attr_names - db_attr_names
    attrs_to_keep   = csv_attr_names & db_attr_names

    # Attributes to DELETE
    if attrs_to_delete.any?
      puts "  ATTRIBUTES TO DELETE (#{attrs_to_delete.size}):"
      attrs_to_delete.each do |name|
        attr = db_attrs[name]
        val_count     = attr.product_attribute_values.size
        variant_count = VariantAttributeValue
          .joins(:product_attribute_value)
          .where(product_attribute_values: { product_attribute_id: attr.id })
          .count
        product_count = attr.products.count
        puts "    ✗ #{name} (#{val_count} values, #{product_count} products, #{variant_count} variant links)"
      end
    else
      puts "  No attributes to delete."
    end

    # Attributes to CREATE
    if attrs_to_create.any?
      puts "\n  ATTRIBUTES TO CREATE (#{attrs_to_create.size}):"
      attrs_to_create.each do |name|
        vals = csv_attributes[name].to_a.sort
        puts "    + #{name} (#{vals.size} values): #{vals.join(', ')}"
      end
    else
      puts "\n  No attributes to create."
    end

    # Attributes to KEEP — show value diffs
    if attrs_to_keep.any?
      puts "\n  ATTRIBUTES TO KEEP (#{attrs_to_keep.size}):"
      attrs_to_keep.sort.each do |name|
        attr       = db_attrs[name]
        db_values  = attr.product_attribute_values.pluck(:value).to_set
        csv_values = csv_attributes[name]

        to_add    = csv_values - db_values
        to_remove = db_values - csv_values
        unchanged = db_values & csv_values

        status_parts = []
        status_parts << "#{unchanged.size} kept" if unchanged.any?
        status_parts << "#{to_add.size} to add" if to_add.any?
        status_parts << "#{to_remove.size} to remove" if to_remove.any?

        puts "    ≈ #{name} (#{status_parts.join(', ')})"
        to_add.sort.each    { |v| puts "        + #{v}" } if to_add.any?
        to_remove.sort.each { |v| puts "        - #{v}" } if to_remove.any?
      end
    end

    # Summary counts
    products_to_relink = product_attr_map.size
    variants_to_relink = variant_attr_map.values.sum { |h| h.size } - ambiguous.sum { |a| a[:count] }

    puts "\n  SUMMARY:"
    puts "    Attributes to delete:  #{attrs_to_delete.size}"
    puts "    Attributes to create:  #{attrs_to_create.size}"
    puts "    Attributes to keep:    #{attrs_to_keep.size}"
    puts "    Products to re-link:   #{products_to_relink}"
    puts "    Variants to re-link:   #{variants_to_relink}"
    puts "    Ambiguous (skipped):   #{ambiguous.size}"

    if dry_run
      puts "\n" + "=" * 70
      puts "DRY RUN complete. Run with 'execute' to apply changes."
      puts "=" * 70
      next
    end

    # ── Phase 3: Execute cleanup ────────────────────────────────────────

    puts "\n[Phase 3] Executing cleanup...\n\n"

    stats = {
      attrs_deleted: 0,
      attrs_created: 0,
      values_created: 0,
      values_removed: 0,
      products_relinked: 0,
      variants_relinked: 0,
      variants_skipped: 0,
      errors: []
    }

    ActiveRecord::Base.transaction do
      # 3a. Delete unwanted attributes (cascades to values + join records)
      attrs_to_delete.each do |name|
        attr = db_attrs[name]
        puts "  Deleting attribute: #{name} (id=#{attr.id})..."
        attr.destroy!
        stats[:attrs_deleted] += 1
      end

      # 3b. Create missing attributes + all normalized values
      attr_record_cache = {}

      # First, cache existing kept attributes
      attrs_to_keep.each do |name|
        attr_record_cache[name] = org.product_attributes.find_by!(name: name)
      end

      # Create new attributes
      attrs_to_create.each do |name|
        slug = unique_attr_slug(org, name)
        attr = org.product_attributes.create!(name: name, slug: slug, active: true)
        attr_record_cache[name] = attr
        stats[:attrs_created] += 1
        puts "  Created attribute: #{name} (slug=#{slug})"
      end

      # 3c. Sync attribute values — add missing, remove extra
      value_record_cache = {} # "AttrName:value" => record

      csv_attributes.each do |attr_name, csv_values|
        attr = attr_record_cache[attr_name]
        next unless attr

        existing_values = attr.product_attribute_values.index_by(&:value)

        # Add missing values
        csv_values.each do |val|
          if existing_values[val]
            value_record_cache["#{attr_name}:#{val}"] = existing_values[val]
          else
            slug = unique_value_slug(attr, val)
            record = attr.product_attribute_values.create!(value: val, slug: slug, active: true)
            value_record_cache["#{attr_name}:#{val}"] = record
            stats[:values_created] += 1
            puts "  Created value: #{attr_name} → #{val}"
          end
        end

        # Remove values not in CSV
        values_to_remove = existing_values.keys.to_set - csv_values
        values_to_remove.each do |val|
          record = existing_values[val]
          variant_links = record.variant_attribute_values.count
          puts "  Removing value: #{attr_name} → #{val} (#{variant_links} variant links)"
          record.destroy!
          stats[:values_removed] += 1
        end
      end

      # 3d. Re-link products to attributes and available values
      puts "\n  Re-linking products to attributes..."
      product_attr_map.each do |sku, attr_map|
        product = org.products.find_by(sku: sku)
        unless product
          stats[:errors] << "Product not found: #{sku}"
          next
        end

        # Clear existing links
        product.product_product_attributes.destroy_all
        product.product_available_values.destroy_all

        # Rebuild
        attr_map.each do |attr_name, values|
          attr = attr_record_cache[attr_name]
          unless attr
            stats[:errors] << "Attribute not found in cache: #{attr_name} (product #{sku})"
            next
          end

          product.product_product_attributes.find_or_create_by!(product_attribute: attr)

          values.each do |val|
            val_record = value_record_cache["#{attr_name}:#{val}"]
            unless val_record
              stats[:errors] << "Value not found in cache: #{attr_name}:#{val} (product #{sku})"
              next
            end
            product.product_available_values.find_or_create_by!(product_attribute_value: val_record)
          end
        end

        stats[:products_relinked] += 1
      end

      # 3e. Re-link variants to attribute values
      puts "\n  Re-linking variants to attribute values..."
      variant_attr_map.each do |parent_sku, variants|
        product = org.products.find_by(sku: parent_sku)
        unless product
          stats[:errors] << "Parent product not found: #{parent_sku}"
          next
        end

        variants.each do |var_name, attr_vals|
          # Skip ambiguous names
          if variant_name_counts[parent_sku][var_name] > 1
            stats[:variants_skipped] += 1
            next
          end

          matching = product.product_variants.where(name: var_name)

          if matching.count == 0
            stats[:errors] << "Variant not found: '#{var_name}' under #{parent_sku}"
            next
          elsif matching.count > 1
            stats[:errors] << "Multiple DB variants for '#{var_name}' under #{parent_sku} (#{matching.count})"
            stats[:variants_skipped] += 1
            next
          end

          variant = matching.first

          # Clear old links and rebuild
          variant.variant_attribute_values.destroy_all

          attr_vals.each do |attr_name, val|
            val_record = value_record_cache["#{attr_name}:#{val}"]
            unless val_record
              stats[:errors] << "Value not in cache: #{attr_name}:#{val} (variant '#{var_name}' / #{parent_sku})"
              next
            end
            variant.variant_attribute_values.create!(product_attribute_value: val_record)
          end

          stats[:variants_relinked] += 1
        end
      end
    end

    # ── Summary ─────────────────────────────────────────────────────────

    puts "\n" + "=" * 70
    puts "Cleanup complete!"
    puts "  Attributes deleted:    #{stats[:attrs_deleted]}"
    puts "  Attributes created:    #{stats[:attrs_created]}"
    puts "  Values created:        #{stats[:values_created]}"
    puts "  Values removed:        #{stats[:values_removed]}"
    puts "  Products re-linked:    #{stats[:products_relinked]}"
    puts "  Variants re-linked:    #{stats[:variants_relinked]}"
    puts "  Variants skipped:      #{stats[:variants_skipped]}"
    puts "  Errors:                #{stats[:errors].size}"

    if stats[:errors].any?
      puts "\nErrors:"
      stats[:errors].each { |e| puts "  • #{e}" }
    end

    puts "=" * 70
  end

  private

  # ── Normalization rules ─────────────────────────────────────────────

  def normalize_value(attr_name, value)
    val = value.strip

    case attr_name
    when "Espessura"
      # Fix comma typos: "3, cm" → "3 cm", "4, cm" → "4 cm"
      val = val.gsub(/(\d+),\s*cm/, '\1 cm')

    when "Tamanho"
      # Add spaces around x: "9x13" → "9 x 13"
      val = val.gsub(/(\d)x(\d)/, '\1 x \2')

      # Remove leading zeros in dimensions: "08" → "8"
      val = val.gsub(/\b0+(\d+)/, '\1')

      # Fix dash spacing: "8 x 5 -13 x 17" → "8 x 5-13 x 17"
      val = val.gsub(/\s+-/, '-')

      # Fix comma typo before "cm": "18-4,cm" → "18-4cm"
      val = val.gsub(/,cm/, 'cm')

      # Normalize "Alt." prefix: "Alt.19cm" → "Alt. 19cm"
      val = val.gsub(/Alt\.(\d)/, 'Alt. \1')

      # Capitalize "base": "base 10cm" → "Base 10cm"
      val = val.sub(/\bbase\b/, 'Base')
    end

    val
  end

  # ── Slug helpers ────────────────────────────────────────────────────

  def unique_attr_slug(org, name)
    base = name.parameterize
    base = "attr-#{SecureRandom.hex(4)}" if base.blank?
    slug = base
    counter = 1
    while org.product_attributes.exists?(slug: slug)
      counter += 1
      slug = "#{base}-#{counter}"
    end
    slug
  end

  def unique_value_slug(attr, value)
    base = value.parameterize
    base = "value-#{SecureRandom.hex(4)}" if base.blank?
    slug = base
    counter = 1
    while attr.product_attribute_values.exists?(slug: slug)
      counter += 1
      slug = "#{base}-#{counter}"
    end
    slug
  end
end
