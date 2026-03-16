class DiscountEmailNotification < ApplicationRecord
  belongs_to :notifiable, polymorphic: true
  belongs_to :organisation
  belongs_to :sent_by, class_name: 'Member', optional: true

  scope :pending, -> { where(status: 'pending') }
  scope :sent, -> { where(status: 'sent') }

  def send_email!(member:)
    case notifiable_type
    when 'ProductDiscount', 'OrderDiscount'
      CustomerMailer.with(discount: notifiable, organisation: organisation).notify_clients_about_discount.deliver_now
    when 'CustomerDiscount', 'CustomerProductDiscount'
      CustomerMailer.with(discount: notifiable, organisation: organisation).notify_customer_about_discount.deliver_now
    when 'PromoCode'
      CustomerMailer.with(promo_code: notifiable, organisation: organisation).notify_promo_code.deliver_now
    end

    update!(status: 'sent', sent_at: Time.current, sent_by: member)
  end

  def self.recipient_count_for(notifiable, organisation)
    active_with_email = { active: true, email_notifications_enabled: true }
    case notifiable
    when ProductDiscount, OrderDiscount
      organisation.customers.where(active_with_email).count
    when CustomerDiscount, CustomerProductDiscount
      c = notifiable.customer
      c.active? && c.email_notifications_enabled? ? 1 : 0
    when PromoCode
      if notifiable.eligibility == 'all_customers'
        organisation.customers.where(active_with_email).count
      else
        notifiable.eligible_customers.where(active_with_email).count
      end
    else
      0
    end
  end
end
