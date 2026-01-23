# Preview all emails at http://localhost:3000/rails/mailers/customer_mailer
class CustomerMailerPreview < ActionMailer::Preview
  def confirm_order
    order = Order.placed.last
    raise "No placed orders found. Create an order first." unless order
    customer = order.customer
    CustomerMailer.with(customer: customer, order: order).confirm_order
  end

  def invitation_instructions
    customer = Customer.last
    raise "No customers found. Create a customer first." unless customer
    CustomerMailer.invitation_instructions(customer, "preview-token-123")
  end

  def reset_password_instructions
    customer = Customer.last
    raise "No customers found. Create a customer first." unless customer
    CustomerMailer.reset_password_instructions(customer, "preview-token-123")
  end

  def notify_clients_about_discount_product
    product_discount = ProductDiscount.last
    raise "No product discounts found. Create a product discount first." unless product_discount
    organisation = product_discount.organisation
    CustomerMailer.with(discount: product_discount, organisation: organisation).notify_clients_about_discount
  end

  def notify_clients_about_discount_order
    order_discount = OrderDiscount.last
    raise "No order discounts found. Create an order discount first." unless order_discount
    organisation = order_discount.organisation
    CustomerMailer.with(discount: order_discount, organisation: organisation).notify_clients_about_discount
  end

  def notify_customer_about_discount_customer
    customer_discount = CustomerDiscount.last
    raise "No customer discounts found. Create a customer discount first." unless customer_discount
    organisation = customer_discount.organisation
    CustomerMailer.with(discount: customer_discount, organisation: organisation).notify_customer_about_discount
  end

  def notify_customer_about_discount_customer_product
    customer_product_discount = CustomerProductDiscount.last
    raise "No customer product discounts found. Create a customer product discount first." unless customer_product_discount
    organisation = customer_product_discount.organisation
    CustomerMailer.with(discount: customer_product_discount, organisation: organisation).notify_customer_about_discount
  end
end
