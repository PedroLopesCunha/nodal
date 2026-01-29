class RenameProductPhotoToPhotos < ActiveRecord::Migration[7.1]
  def up
    # Rename existing 'photo' attachments to 'photos' for Product records
    ActiveStorage::Attachment
      .where(record_type: "Product", name: "photo")
      .update_all(name: "photos")
  end

  def down
    # Revert back to 'photo' if needed
    ActiveStorage::Attachment
      .where(record_type: "Product", name: "photos")
      .update_all(name: "photo")
  end
end
