module Bo
  module SalesRep
    # Personal carteira view for any OrgMember with `is_sales_rep: true`.
    # Lists the customers they're assigned to, with last-order metadata.
    # Owners/admins who are also reps see only customers explicitly assigned
    # to them here — the full clients list is at /bo/customers.
    class CarteiraController < Bo::BaseController
      def index
        unless current_org_member&.is_sales_rep?
          flash[:alert] = "Esta página é só para vendedores."
          redirect_to bo_path(org_slug: current_organisation.slug) and return
        end

        skip_authorization
        skip_policy_scope

        @customers = current_organisation
                       .customers
                       .joins(:customer_assignment)
                       .where(customer_assignments: { org_member_id: current_org_member.id })
                       .includes(:customer_assignment)

        # Pre-load last order date per customer to avoid N+1
        last_orders = current_organisation
                        .orders
                        .placed
                        .where(customer_id: @customers.pluck(:id))
                        .group(:customer_id)
                        .maximum(:placed_at)
        @last_order_at = last_orders

        @customers = @customers.order(:company_name)

        # "Meus números": all placed orders from customers in this rep's
        # carteira — self-service by the customer counts too, since the rep
        # owns the relationship. Plus any orders the rep placed for customers
        # outside the carteira (e.g. owner+rep doing vacation coverage).
        carteira_customer_ids = current_org_member.customer_assignments.pluck(:customer_id)
        rep_orders = current_organisation.orders.placed.where(
          "orders.customer_id IN (?) OR orders.sales_rep_id = ?",
          carteira_customer_ids,
          current_org_member.id
        )
        currency = current_organisation.currency

        this_month_orders = rep_orders.where(placed_at: Time.current.beginning_of_month..Time.current.end_of_month)
        last_month_orders = rep_orders.where(placed_at: 1.month.ago.beginning_of_month..1.month.ago.end_of_month)

        @kpi_orders_this_month = this_month_orders.count
        @kpi_orders_last_month = last_month_orders.count

        this_month_total_cents = this_month_orders.sum { |o| o.grand_total.cents rescue 0 }
        last_month_total_cents = last_month_orders.sum { |o| o.grand_total.cents rescue 0 }

        @kpi_revenue_this_month = Money.new(this_month_total_cents, currency)
        @kpi_revenue_last_month = Money.new(last_month_total_cents, currency)

        @kpi_aov_this_month = @kpi_orders_this_month > 0 ? Money.new(this_month_total_cents / @kpi_orders_this_month, currency) : Money.new(0, currency)
        @kpi_aov_last_month = @kpi_orders_last_month > 0 ? Money.new(last_month_total_cents / @kpi_orders_last_month, currency) : Money.new(0, currency)
      end
    end
  end
end
