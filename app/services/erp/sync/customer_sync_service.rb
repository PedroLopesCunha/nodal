module Erp
  module Sync
    class CustomerSyncService < BaseSyncService
      protected

      def entity_type
        'customers'
      end

      GC_INTERVAL = 500

      def perform_sync
        count = 0
        adapter.each_customer do |customer_data|
          sync_customer(customer_data)
          count += 1
          GC.start if (count % GC_INTERVAL).zero?
        end
      end

      private

      def sync_customer(data)
        external_id = data[:external_id]

        unless external_id.present?
          sync_log.increment_failed!('unknown', 'Missing external_id')
          return
        end

        customer = find_or_initialize_customer(external_id, data[:email])
        was_new = customer.new_record?

        # Customer holds only ERP-owned fields after the customer/login split
        # (auth + personal preferences live on CustomerUser, which is never
        # synced from ERP). So ERP wins, always — no identity guard.
        update_customer_attributes(customer, data, was_new)

        if was_new || customer.changed?
          changes_snapshot = customer.changes
          if customer.save
            customer.mark_synced!(source: external_source)
            if was_new
              record_changes(external_id, 'created', customer)
              sync_log.increment_created!
            else
              record_changes(external_id, 'updated', customer, changes_snapshot)
              sync_log.increment_updated!
            end
          else
            sync_log.increment_failed!(external_id, customer.errors.full_messages.join(', '))
            return
          end
        else
          sync_log.increment_processed!
        end

        # Always run for both new and existing customers, regardless of
        # identity guard. Lenient: per-address failures are logged but
        # don't fail the customer sync.
        sync_addresses(customer, data)
      rescue StandardError => e
        sync_log.increment_failed!(data[:external_id], e.message)
      end

      # Syncs billing + shipping addresses for a customer.
      # Billing: ERP overwrites the existing record (or creates one).
      # Shipping: never replaces; only adds when the ERP-provided address
      # doesn't match any existing active shipping by content fingerprint.
      # Failures on either side are logged but don't break customer sync.
      def sync_addresses(customer, data)
        if data[:billing_address].present?
          begin
            sync_billing_address(customer, data[:billing_address])
          rescue StandardError => e
            Rails.logger.warn("[ERP sync] billing address failed for customer external_id=#{customer.external_id}: #{e.message}")
          end
        end

        if data[:shipping_address].present?
          begin
            sync_shipping_address(customer, data[:shipping_address])
          rescue StandardError => e
            Rails.logger.warn("[ERP sync] shipping address failed for customer external_id=#{customer.external_id}: #{e.message}")
          end
        end
      end

      def sync_billing_address(customer, attrs)
        billing = customer.billing_address_with_archived ||
                  customer.build_billing_address_with_archived(address_type: "billing")

        # Reset every known address field before applying ERP values so
        # unmapped fields don't keep stale data (e.g. a street_nr from a
        # one-off CSV import when the ERP only exposes a combined street).
        reset_attrs = { street_name: nil, street_nr: nil, postal_code: nil, city: nil, country: nil }

        billing.assign_attributes(
          reset_attrs.merge(attrs).merge(
            address_type: "billing",
            external_source: external_source,
            last_synced_at: Time.current,
            active: true
          )
        )
        billing.save! if billing.changed?
      end

      def sync_shipping_address(customer, attrs)
        new_fp = Address.fingerprint_for(
          street_name: attrs[:street_name],
          street_nr: attrs[:street_nr],
          postal_code: attrs[:postal_code],
          city: attrs[:city],
          country: attrs[:country]
        )

        existing_match = customer.shipping_addresses_with_archived
                                 .active
                                 .find { |a| a.fingerprint == new_fp }
        return if existing_match

        customer.shipping_addresses_with_archived.create!(
          attrs.merge(
            address_type: "shipping",
            external_source: external_source,
            last_synced_at: Time.current,
            active: true
          )
        )
      end

      def find_or_initialize_customer(external_id, email)
        # First try to find by external_id
        customer = organisation.customers.find_by(
          external_id: external_id,
          external_source: external_source
        )

        return customer if customer

        # If not found by external_id, try by email (for linking existing customers)
        if email.present?
          customer = organisation.customers.find_by(email: email)
          if customer && customer.external_id.blank?
            customer.external_id = external_id
            customer.external_source = external_source
            return customer
          end
        end

        # Create new customer
        organisation.customers.new(
          external_id: external_id,
          external_source: external_source
        )
      end

      def update_customer_attributes(customer, data, _is_new)
        customer.assign_attributes(
          company_name: data[:company_name],
          contact_name: data[:contact_name],
          email: data[:email],
          contact_phone: data[:phone],
          taxpayer_id: data[:taxpayer_id],
          active: data[:active]
        )
      end

      def record_changes(external_id, action, customer, changes_snapshot = nil)
        changes = if action == 'created'
          {
            company_name: customer.company_name,
            contact_name: customer.contact_name,
            email: customer.email
          }
        else
          changes_snapshot || customer.changes
        end

        sync_log.add_change(external_id, 'Customer', action, changes)
      end
    end
  end
end
