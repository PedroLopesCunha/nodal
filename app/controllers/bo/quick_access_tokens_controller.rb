class Bo::QuickAccessTokensController < Bo::BaseController
  before_action :set_customer
  before_action :set_customer_user
  before_action :load_token, only: [:show, :destroy, :download]

  FORMATS = %w[card sheet stickers digital].freeze

  def show
    authorize @customer_user, :edit?, policy_class: CustomerUserPolicy
    # Renders the modal contents (or full page) showing the active token,
    # its QR preview, and the download/regenerate/revoke actions.
  end

  def create
    authorize @customer_user, :edit?, policy_class: CustomerUserPolicy

    unless @customer_user.invitation_status == :active
      redirect_to bo_customer_customer_user_quick_access_token_path(
                    org_slug: params[:org_slug],
                    customer_id: @customer.id,
                    customer_user_id: @customer_user.id
                  ),
                  alert: t("bo.quick_access_tokens.flash.user_not_ready") and return
    end

    @token = QuickAccessToken.generate_for(@customer_user, created_by: current_member)
    redirect_to bo_customer_customer_user_quick_access_token_path(
                  org_slug: params[:org_slug],
                  customer_id: @customer.id,
                  customer_user_id: @customer_user.id
                ),
                notice: t("bo.quick_access_tokens.flash.generated")
  end

  def destroy
    authorize @customer_user, :edit?, policy_class: CustomerUserPolicy
    @token&.revoke!
    redirect_to bo_customer_path(params[:org_slug], @customer),
                notice: t("bo.quick_access_tokens.flash.revoked")
  end

  def download
    authorize @customer_user, :edit?, policy_class: CustomerUserPolicy

    unless @token&.active?
      redirect_to bo_customer_path(params[:org_slug], @customer),
                  alert: t("bo.quick_access_tokens.flash.not_active") and return
    end

    fmt = FORMATS.include?(params[:layout]) ? params[:layout] : "card"
    @layout = fmt
    @qr_url = quick_access_url(org_slug: @customer.organisation.slug, token: @token.token)
    @qr_svg = qr_svg(@qr_url)

    html = render_to_string(template: "bo/quick_access_tokens/pdf_#{fmt}", layout: false)

    if fmt == "digital"
      png = Grover.new(html, **grover_options(fmt)).to_png
      send_data png, type: "image/png", disposition: "attachment",
                     filename: pdf_filename("digital", "png")
    else
      pdf = Grover.new(html, **grover_options(fmt)).to_pdf
      send_data pdf, type: "application/pdf", disposition: "attachment",
                     filename: pdf_filename(fmt, "pdf")
    end
  end

  private

  def set_customer
    @customer = current_organisation.customers.find(params[:customer_id])
  end

  def set_customer_user
    @customer_user = @customer.customer_users.find(params[:customer_user_id])
  end

  def load_token
    @token = @customer_user.quick_access_tokens.active.first
  end

  def qr_svg(data)
    qr = RQRCode::QRCode.new(data, level: :m)
    qr.as_svg(
      offset: 0,
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true,
      viewbox: true # outputs <svg viewBox="..."> with no fixed width/height so CSS can scale it
    )
  end

  def grover_options(format)
    case format
    when "card"
      { format: nil, width: "85mm", height: "55mm", margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }
    when "sheet"
      { format: "A4", margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }
    when "stickers"
      # Avery L7163: A4, 8 labels (2 cols × 4 rows), 99.1×67.7mm each.
      { format: "A4", margin: { top: "0", bottom: "0", left: "0", right: "0" }, prefer_css_page_size: true }
    when "digital"
      # Square PNG, instagram / WhatsApp friendly.
      { width: "1080px", height: "1080px", margin: { top: "0", bottom: "0", left: "0", right: "0" }, viewport: { width: 1080, height: 1080 }, full_page: false, omit_background: false }
    else
      { format: "A4" }
    end
  end

  def pdf_filename(layout, ext)
    safe_name = @customer.company_name.to_s.parameterize.presence || "cliente"
    "qr-#{layout}-#{safe_name}.#{ext}"
  end
end
