module Erp
  module Adapters
    class CustomApiAdapter < BaseAdapter
      def valid_credentials?
        credentials[:base_url].present? && credentials[:api_key].present?
      end

      def test_connection
        return { success: false, error: 'Missing credentials' } unless valid_credentials?

        response = http_client.get(products_url) do |req|
          apply_auth(req)
        end

        { success: true, message: 'Connection successful' }
      rescue Faraday::Error => e
        { success: false, error: extract_error_message(e) }
      end

      def fetch_products
        return [] unless valid_credentials?

        response = http_client.get(products_url) do |req|
          apply_auth(req)
        end

        normalize_products(response.body)
      rescue Faraday::Error => e
        handle_request_error(e)
      end

      def fetch_customers
        return [] unless valid_credentials?

        response = http_client.get(customers_url) do |req|
          apply_auth(req)
        end

        normalize_customers(response.body)
      rescue Faraday::Error => e
        handle_request_error(e)
      end

      private

      def base_url
        credentials[:base_url].to_s.chomp('/')
      end

      def products_endpoint
        credentials[:products_endpoint].presence || '/products'
      end

      def customers_endpoint
        credentials[:customers_endpoint].presence || '/customers'
      end

      def products_url
        "#{base_url}#{products_endpoint}"
      end

      def customers_url
        "#{base_url}#{customers_endpoint}"
      end

      def apply_auth(request)
        api_key = credentials[:api_key]

        if credentials[:auth_type] == 'bearer'
          request.headers['Authorization'] = "Bearer #{api_key}"
        else
          request.headers['X-API-Key'] = api_key
        end
      end

      def normalize_products(body)
        data = extract_data(body)
        data.map { |item| normalize_product(item) }
      end

      def normalize_product(item)
        {
          external_id: item['id']&.to_s,
          name: item['name'] || item['title'] || item['product_name'],
          sku: item['sku'] || item['code'] || item['product_code'],
          description: item['description'] || item['desc'],
          unit_price_cents: parse_price(item['price'] || item['unit_price']),
          available: parse_boolean(item['available'] || item['active'] || item['enabled'] || true),
          raw_data: item
        }.compact
      end

      def normalize_customers(body)
        data = extract_data(body)
        data.map { |item| normalize_customer(item) }
      end

      def normalize_customer(item)
        {
          external_id: item['id']&.to_s,
          company_name: item['company_name'] || item['company'] || item['name'],
          contact_name: item['contact_name'] || item['contact'] || item['primary_contact'],
          email: item['email'] || item['contact_email'],
          phone: item['phone'] || item['telephone'] || item['contact_phone'],
          active: parse_boolean(item['active'] || item['enabled'] || true),
          raw_data: item
        }.compact
      end

      def extract_data(body)
        return body if body.is_a?(Array)
        return body['data'] if body.is_a?(Hash) && body['data'].is_a?(Array)
        return body['items'] if body.is_a?(Hash) && body['items'].is_a?(Array)
        return body['results'] if body.is_a?(Hash) && body['results'].is_a?(Array)

        []
      end

      def parse_price(value)
        return nil if value.nil?

        case value
        when Integer
          value
        when Float
          (value * 100).round
        when String
          (value.to_f * 100).round
        else
          nil
        end
      end

      def parse_boolean(value)
        return true if value.nil?
        return value if [true, false].include?(value)
        return true if value.to_s.downcase.in?(%w[true 1 yes active enabled])

        false
      end

      def extract_error_message(error)
        case error
        when Faraday::ConnectionFailed
          "Could not connect to #{base_url}"
        when Faraday::TimeoutError
          "Connection timed out"
        when Faraday::ClientError
          status = error.response&.dig(:status) || 'unknown'
          "API returned status #{status}"
        else
          error.message
        end
      end
    end
  end
end
