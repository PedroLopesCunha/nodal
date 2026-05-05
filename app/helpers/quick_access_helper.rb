module QuickAccessHelper
  # Returns a data: URL for the organisation logo so it can be embedded
  # directly into PDF / PNG templates rendered by Grover. Grover runs
  # headless Chrome inside the dyno and would not be able to fetch a
  # localhost / Cloudinary URL reliably from there, so embedding the
  # bytes is the robust path.
  def org_logo_data_url(organisation)
    return nil unless organisation&.logo&.attached?

    blob = organisation.logo.blob
    "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
  end
end
