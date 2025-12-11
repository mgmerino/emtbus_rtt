# frozen_string_literal: true

require_relative "emtbus_rtt/version"
require_relative "emtbus_rtt/errors"
require_relative "emtbus_rtt/client"

module EmtbusRtt
  class << self
    attr_accessor :client_id, :pass_key

    # Configure the gem with default credentials
    #
    # @example
    #   EmtbusRtt.configure do |config|
    #     config.client_id = 'your_client_id'
    #     config.pass_key = 'your_pass_key'
    #   end
    def configure
      yield self
    end

    # Create a new client instance with default or provided credentials
    #
    # @param options [Hash] Options to pass to Client.new
    # @return [Client] A new client instance
    def client(**options)
      Client.new(
        client_id: options[:client_id] || client_id,
        pass_key: options[:pass_key] || pass_key,
        **options.except(:client_id, :pass_key)
      )
    end
  end
end
