# frozen_string_literal: true

module EmtbusRtt
  # Base error class for all EmtbusRtt errors
  class Error < StandardError; end

  # Raised when there's a configuration problem (missing credentials, etc.)
  class ConfigurationError < Error; end

  # Raised when authentication fails or token is invalid
  class AuthenticationError < Error; end

  # Raised when the API returns an error response
  class ApiError < Error
    attr_reader :code, :response

    def initialize(message, code: nil, response: nil)
      @code = code
      @response = response
      super(message)
    end
  end
end
