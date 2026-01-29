module Erp
  class ConnectionError < StandardError
    def initialize(message = "Failed to connect to ERP system")
      super(message)
    end
  end
end
