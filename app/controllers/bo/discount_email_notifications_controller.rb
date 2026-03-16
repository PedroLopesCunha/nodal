class Bo::DiscountEmailNotificationsController < Bo::BaseController
  def send_email
    @notification = current_organisation.discount_email_notifications.pending.find(params[:id])
    authorize @notification

    begin
      @notification.send_email!(member: current_member)
      redirect_to bo_pricing_path(params[:org_slug], tab: tab_for(@notification)),
                  notice: t('bo.pricing.email_notifications.sent_success')
    rescue => e
      Rails.logger.error("Failed to send discount email notification: #{e.message}")
      redirect_to bo_pricing_path(params[:org_slug], tab: tab_for(@notification)),
                  alert: t('bo.pricing.email_notifications.sent_error')
    end
  end

  def recipients
    @notification = current_organisation.discount_email_notifications.find(params[:id])
    authorize @notification, :send_email?

    @recipients = recipients_for(@notification)
    render partial: 'bo/shared/email_notification_recipients', layout: false
  end

  private

  def recipients_for(notification)
    notifiable = notification.notifiable
    active_with_email = { active: true, email_notifications_enabled: true }
    case notifiable
    when ProductDiscount, OrderDiscount
      current_organisation.customers.where(active_with_email)
        .order(:company_name).select(:company_name, :email)
    when CustomerDiscount, CustomerProductDiscount
      c = notifiable.customer
      c.active? && c.email_notifications_enabled? ? [c] : []
    when PromoCode
      if notifiable.eligibility == 'all_customers'
        current_organisation.customers.where(active_with_email)
          .order(:company_name).select(:company_name, :email)
      else
        notifiable.eligible_customers.where(active_with_email)
          .order(:company_name).select(:company_name, :email)
      end
    else
      []
    end
  end

  def tab_for(notification)
    case notification.notifiable_type
    when 'ProductDiscount' then 'product_discounts'
    when 'OrderDiscount' then 'order_tiers'
    when 'CustomerDiscount' then 'client_tiers'
    when 'CustomerProductDiscount' then 'custom_pricing'
    when 'PromoCode' then 'promo_codes'
    end
  end
end
