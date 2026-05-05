class QuickAccessPdfRenderer
  PdfFormatError = Class.new(StandardError)

  GROVER_OPTIONS = {
    card:    { format: nil, width: "85mm",  height: "55mm",  margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }.freeze,
    sheet:   { format: "A4",                                margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }.freeze,
    digital: { format: nil, width: "105mm", height: "148mm", margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }.freeze
  }.freeze

  def initialize(token:, layout:)
    @token = token
    @layout = layout.to_sym
    raise PdfFormatError, "unknown layout #{layout}" unless GROVER_OPTIONS.key?(@layout)
  end

  def render_pdf
    Grover.new(html, **GROVER_OPTIONS.fetch(@layout)).to_pdf
  end

  private

  def html
    customer_user = @token.customer_user
    customer = customer_user.customer
    qr_url = Rails.application.routes.url_helpers.quick_access_url(
      org_slug: customer.organisation.slug,
      token: @token.token,
      **url_options
    )

    ApplicationController.render(
      template: "bo/quick_access_tokens/pdf_#{@layout}",
      layout: false,
      assigns: {
        token: @token,
        customer: customer,
        customer_user: customer_user,
        qr_url: qr_url,
        qr_svg: build_qr_svg(qr_url)
      }
    )
  end

  def build_qr_svg(data)
    qr = RQRCode::QRCode.new(data, level: :m)
    qr.as_svg(
      offset: 0,
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true,
      viewbox: true
    )
  end

  # The renderer runs in a background job (no request context), so we
  # need to give Rails URL helpers an explicit host. Production sets
  # APP_HOST and uses HTTPS; dev falls back to localhost:3000.
  def url_options
    if Rails.env.production?
      { host: ENV.fetch("APP_HOST", "www.nodal-seiri.dev"), protocol: "https" }
    else
      { host: "localhost", port: 3000, protocol: "http" }
    end
  end
end
