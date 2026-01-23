module Erp
  class ConfigurationError < StandardError
    def initialize(message = "ERP configuration is invalid")
      super(message)
    end
  end
end
