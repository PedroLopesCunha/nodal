# frozen_string_literal: true

require "open-uri"
require "csv"

namespace :import do
  desc "Import product images from WordPress CSV export"
  task :images_from_csv, [:csv_path, :org_slug] => :environment do |t, args|
    csv_path = args[:csv_path]
    org_slug = args[:org_slug]

    # Validate arguments
    unless csv_path && org_slug
      puts "Usage: rails 'import:images_from_csv[path/to/file.csv,org-slug]'"
      exit 1
    end

    unless File.exist?(csv_path)
      puts "Error: CSV file not found at #{csv_path}"
      exit 1
    end

    # Find organisation
    organisation = Organisation.find_by(slug: org_slug)
    unless organisation
      puts "Error: Organisation '#{org_slug}' not found"
      exit 1
    end

    puts "Importing images for organisation: #{organisation.name}"
    puts "-" * 50

    # Counters
    success_count = 0
    skipped_count = 0
    error_count = 0
    not_found_count = 0

    # Parse CSV (comma delimiter)
    CSV.foreach(csv_path, headers: true, liberal_parsing: true) do |row|
      sku = row["REF"]&.strip
      image_urls = row["Imagens"]&.strip

      # Handle multiple URLs (comma-separated) - use only the first one
      image_url = image_urls&.split(",")&.first&.strip

      # Skip rows with missing data
      if sku.blank?
        puts "SKIP: Missing SKU"
        skipped_count += 1
        next
      end

      if image_url.blank?
        puts "SKIP: [#{sku}] No image URL"
        skipped_count += 1
        next
      end

      # Find product by SKU within organisation
      product = organisation.products.find_by(sku: sku)
      unless product
        puts "NOT FOUND: [#{sku}] Product not found"
        not_found_count += 1
        next
      end

      # Skip if product already has an image
      if product.photo_attached?
        puts "SKIP: [#{sku}] #{product.name} - already has image"
        skipped_count += 1
        next
      end

      # Download and attach image
      begin
        # Extract filename from URL
        uri = URI.parse(image_url)
        filename = File.basename(uri.path)

        # Download image
        downloaded_image = URI.open(image_url, read_timeout: 30, open_timeout: 30)

        # Attach to product (uses photos collection)
        product.photos.attach(
          io: downloaded_image,
          filename: filename,
          content_type: downloaded_image.content_type
        )

        puts "SUCCESS: [#{sku}] #{product.name} - attached #{filename}"
        success_count += 1

      rescue OpenURI::HTTPError => e
        puts "ERROR: [#{sku}] HTTP error downloading image: #{e.message}"
        error_count += 1
      rescue URI::InvalidURIError => e
        puts "ERROR: [#{sku}] Invalid URL '#{image_url}': #{e.message}"
        error_count += 1
      rescue Timeout::Error
        puts "ERROR: [#{sku}] Timeout downloading image"
        error_count += 1
      rescue StandardError => e
        puts "ERROR: [#{sku}] #{e.class}: #{e.message}"
        error_count += 1
      end
    end

    # Summary
    puts "-" * 50
    puts "Import complete!"
    puts "  Success:   #{success_count}"
    puts "  Skipped:   #{skipped_count}"
    puts "  Not found: #{not_found_count}"
    puts "  Errors:    #{error_count}"
    puts "  Total:     #{success_count + skipped_count + not_found_count + error_count}"
  end
end
