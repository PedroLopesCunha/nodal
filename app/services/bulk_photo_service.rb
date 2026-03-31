require "zip"

class BulkPhotoService
  Result = Struct.new(:photos_attached, :products_matched, :errors, keyword_init: true)

  def initialize(organisation:, zip_path: nil, images_dir: nil, photo_mode: "append")
    @organisation = organisation
    @zip_path = zip_path
    @images_dir = images_dir
    @photo_mode = photo_mode
    @images_by_sku = {}
  end

  def call
    extract_images_from_zip if @zip_path.present?
    load_images_from_dir if @images_dir.present?

    photos_attached = 0
    products_matched = 0
    errors = []

    # Match photos to products (has_many_attached :photos)
    @organisation.products.where.not(sku: [nil, ""]).find_each do |product|
      begin
        count = attach_photos(product)
        if count > 0
          photos_attached += count
          products_matched += 1
        end
      rescue => e
        errors << { row: nil, field: product.sku, message: e.message }
      end
    end

    # Match photos to variants (has_one_attached :photo)
    @organisation.product_variants.where.not(sku: [nil, ""]).where(is_default: false).find_each do |variant|
      begin
        count = attach_variant_photo(variant)
        if count > 0
          photos_attached += count
          products_matched += 1
        end
      rescue => e
        errors << { row: nil, field: variant.sku, message: e.message }
      end
    end

    Result.new(photos_attached: photos_attached, products_matched: products_matched, errors: errors)
  ensure
    cleanup_extracted_images
  end

  private

  def extract_images_from_zip
    return unless @zip_path.present? && File.exist?(@zip_path)

    @extracted_dir = Rails.root.join("tmp", "imports", "images_#{SecureRandom.uuid}").to_s
    FileUtils.mkdir_p(@extracted_dir)

    Zip::File.open(@zip_path) do |zip|
      zip.each do |entry|
        next if entry.directory?
        next if entry.name.start_with?("__MACOSX", ".")

        filename = File.basename(entry.name)
        next unless filename.match?(/\.(jpe?g|png|gif|webp)$/i)

        dest = File.join(@extracted_dir, filename)
        File.open(dest, "wb") { |f| f.write(entry.get_input_stream.read) }

        sku = extract_sku_from_filename(filename)
        next if sku.blank?

        @images_by_sku[sku] ||= []
        @images_by_sku[sku] << dest
      end
    end

    @images_by_sku.each { |_sku, paths| paths.sort_by! { |p| sort_key_for_image(File.basename(p)) } }
  end

  def load_images_from_dir
    return unless @images_dir.present? && File.directory?(@images_dir)

    Dir.glob(File.join(@images_dir, "*.{jpg,jpeg,png,gif,webp}")).each do |path|
      filename = File.basename(path)
      sku = extract_sku_from_filename(filename)
      next if sku.blank?

      @images_by_sku[sku] ||= []
      @images_by_sku[sku] << path
    end

    @images_by_sku.each { |_sku, paths| paths.sort_by! { |p| sort_key_for_image(File.basename(p)) } }
  end

  def extract_sku_from_filename(filename)
    name = File.basename(filename, File.extname(filename))
    sku_part = name.split(/\s+/).first
    return nil if sku_part.blank?
    sku_part
  end

  def find_images_for_sku(sku)
    # Normalize: replace / and : with - for comparison (handles macOS/Windows/Linux)
    normalized_sku = sku.tr("/:", "--")

    # Try exact match first, then normalized
    paths = @images_by_sku[sku] || @images_by_sku[normalized_sku]
    return paths if paths.present?

    # Check with numeric suffix stripped (e.g., SKU-1.jpg matches SKU)
    matching = @images_by_sku.select do |key, _|
      stripped = key.sub(/-\d+$/, "")
      stripped == normalized_sku || stripped == sku
    end
    return nil if matching.empty?
    matching.values.flatten
  end

  def sort_key_for_image(filename)
    name = File.basename(filename, File.extname(filename))
    if name =~ /-(\d+)$/
      [$1.to_i, name]
    else
      [0, name]
    end
  end

  def attach_photos(product)
    sku = product.sku
    return 0 if sku.blank?

    image_paths = find_images_for_sku(sku) || []
    return 0 if image_paths.empty?

    if @photo_mode == "replace" && product.photos.attached?
      product.photos.purge
      product.reload
    end

    count = 0
    image_paths.each do |path|
      next unless File.exist?(path)

      filename = File.basename(path)
      content_type = Marcel::MimeType.for(Pathname.new(path))

      product.photos.attach(
        io: File.open(path),
        filename: filename,
        content_type: content_type
      )
      count += 1
    end

    if count > 0 && product.photos.any?
      first_attachment = product.photos_attachments.order(:id).first
      unless product.photos.any? { |p| p.blob.metadata["main"] }
        first_attachment.blob.update(metadata: first_attachment.blob.metadata.merge("main" => true))
      end
    end

    count
  end

  def attach_variant_photo(variant)
    sku = variant.sku
    return 0 if sku.blank?

    image_paths = find_images_for_sku(sku) || []
    return 0 if image_paths.empty?

    # Variant has_one_attached :photo — use first image only
    path = image_paths.first
    return 0 unless File.exist?(path)

    if @photo_mode == "replace" && variant.photo.attached?
      variant.photo.purge
      variant.reload
    end

    # Skip if already has a photo and mode is append
    return 0 if @photo_mode == "append" && variant.photo.attached?

    filename = File.basename(path)
    content_type = Marcel::MimeType.for(Pathname.new(path))

    variant.photo.attach(
      io: File.open(path),
      filename: filename,
      content_type: content_type
    )

    1
  end

  def cleanup_extracted_images
    FileUtils.rm_rf(@extracted_dir) if @extracted_dir && File.exist?(@extracted_dir)
  end
end
