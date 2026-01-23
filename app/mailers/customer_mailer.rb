class CustomerMailer < ApplicationMailer
  helper :application
  layout 'customer_mailer'
  default template_path: 'customer_mailer'

  def invitation_instructions(record, token, opts = {})
    @organisation = record.organisation
    opts[:org_slug] ||= @organisation.slug
    @token = token
    @resource = record
    mail(to: record.email, subject: "Set your password")
  end

  def reset_password_instructions(record, token, opts = {})
    @organisation = record.organisation
    @token = token
    @resource = record
    mail(to: record.email, subject: "Reset your password")
  end

  def confirm_order
    @customer = params[:customer]
    @order = params[:order]
    @organisation = @order.organisation

    I18n.with_locale(@organisation.default_locale) do
      subject = t('mailers.customer_mailer.confirm_order.subject',
                  order_number: @order.order_number)
      mail(to: @customer.email, subject: subject)
    end
  end

  def notify_clients_about_discount
    @discount = params[:discount]
    @organisation = params[:organisation]
    mailing_list = @organisation.customers.pluck(:email)
    if @discount.has_attribute?(:product_id) # ProductDiscount
      send_product_discount_mail(mailing_list)
    else # Order Discount
      send_order_discount_mail(mailing_list)
    end
  end

  def notify_customer_about_discount
    @discount = params[:discount]
    @organisation = params[:organisation]
    @customer = @discount.customer
    if @discount.has_attribute?(:product_id) # CustomerProductDiscount
      @product = @discount.product
      subject = "New Discount on #{@product.name}"
      mail(to: @customer.email, subject: subject) do |format|
        format.html { render 'customer_product_discount' }
        format.text { render 'customer_product_discount' }
      end
    else # CustomerDiscount
      subject = "New personal Discount for YOU!"
      mail(to: @customer.email, subject: subject) do |format|
        format.html { render 'customer_discount' }
        format.text { render 'customer_discount' }
      end
    end
  end

  private

  def send_product_discount_mail(mailing_list)
    @product = @discount.product
    subject = "New Product Discount on #{@product.name}"
    mail(to: mailing_list, subject: subject)
  end

  def send_order_discount_mail(mailing_list)
    subject = "New Discount on new Order"
    mail(to: mailing_list, subject: subject)
  end
end
