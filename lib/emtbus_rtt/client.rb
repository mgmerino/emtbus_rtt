# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

module EmtbusRtt
  # Main API client for EMT Madrid MobilityLabs API
  # Handles authentication and provides access to API endpoints
  class Client
    BASE_URL = "https://openapi.emtmadrid.es"

    attr_reader :access_token, :token_expiration

    # Initialize a new client
    #
    # @param client_id [String] The X-ClientId for authentication
    # @param pass_key [String] The passKey for authentication
    # @param access_token [String, nil] Optional pre-existing access token
    def initialize(client_id: nil, pass_key: nil, access_token: nil)
      @client_id = client_id || ENV.fetch("EMT_CLIENT_ID", nil)
      @pass_key = pass_key || ENV.fetch("EMT_PASS_KEY", nil)
      @access_token = access_token
      @token_expiration = nil

      validate_credentials! unless @access_token
    end

    # Authenticate with the API and obtain an access token
    #
    # Response codes:
    # - "00": New login successful
    # - "01": Token extended (existing valid token)
    #
    # @return [Hash] The login response data
    # @raise [AuthenticationError] if login fails
    def login
      response = unauthenticated_connection.get("/v1/mobilitylabs/user/login/") do |req|
        req.headers["X-ClientId"] = @client_id
        req.headers["passKey"] = @pass_key
      end

      result = parse_response(response)

      unless %w[00 01].include?(result["code"]) && result["data"]&.first
        raise AuthenticationError, "Login failed: #{result["description"]}"
      end

      data = result["data"].first
      @access_token = data["accessToken"]
      @token_expiration = Time.now + (data["tokenSecExpiration"] || 86_400)

      result
    end

    # Check current authentication status
    #
    # @return [Hash] The whoami response data
    # @raise [AuthenticationError] if not authenticated or token invalid
    def whoami
      response = authenticated_connection.get("/v1/mobilitylabs/user/whoami/")
      parse_response(response)
    end

    # Check if the client has a valid access token
    #
    # @return [Boolean] true if token exists and hasn't expired
    def authenticated?
      return false unless @access_token
      return true unless @token_expiration

      Time.now < @token_expiration
    end

    # Ensure the client is authenticated, logging in if necessary
    #
    # @return [void]
    def ensure_authenticated!
      login unless authenticated?
    end

    # Get bus arrivals for a specific stop
    #
    # @param stop_id [String, Integer] The bus stop ID
    # @param line [String, nil] Optional line filter (use 'all' or nil for all lines)
    # @param options [Hash] Additional options for the request
    # @option options [String] :culture_info Language code ('EN' or 'ES'), defaults to 'ES'
    # @option options [Boolean] :stop_info Whether to include stop information
    # @option options [Boolean] :estimations Whether to include arrival estimations
    # @option options [Boolean] :incidents Whether to include incident information
    # @option options [String] :incidents_date Reference date for incidents (YYYYMMDD format)
    # @return [Hash] The arrivals response data
    def arrivals(stop_id, line: nil, **options)
      with_auth_retry do
        line_param = line || "all"
        url = "/v2/transport/busemtmad/stops/#{stop_id}/arrives/#{line_param}/"

        body = build_arrivals_body(options)

        response = authenticated_connection.post(url) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = body.to_json
        end

        parse_response(response)
      end
    end

    # Get simple ETA for a bus line at a stop
    #
    # @param stop_id [String, Integer] The bus stop ID
    # @param line [String] The bus line number
    # @return [Array<Hash>] Array of ETAs with :minutes, :seconds, and :total_seconds keys
    #   Returns empty array if no buses are arriving
    # @example
    #   client.eta(3112, '146')
    #   # => [{ minutes: 6, seconds: 49, total_seconds: 409 }, { minutes: 12, seconds: 30, total_seconds: 750 }]
    def eta(stop_id, line)
      result = arrivals(stop_id, line: line)

      return [] unless result["code"] == "00" && result["data"]&.first

      arrivals_data = result["data"].first["Arrive"] || []

      arrivals_data
        .map { |arrival| arrival["estimateArrive"] }
        .sort
        .map { |seconds| seconds_to_eta(seconds) }
    end

    # Format an ETA hash as a human-readable string
    #
    # @param eta [Hash] An ETA hash with :minutes and :seconds keys
    # @return [String] Formatted string like "6 min 49 sec" or "Arriving now"
    # @example
    #   client.format_eta({ minutes: 6, seconds: 49, total_seconds: 409 })
    #   # => "6 min 49 sec"
    def format_eta(eta)
      self.class.format_eta(eta)
    end

    # Format an ETA hash as a human-readable string (class method)
    #
    # @param eta [Hash] An ETA hash with :minutes and :seconds keys
    # @return [String] Formatted string like "6 min 49 sec" or "Arriving now"
    def self.format_eta(eta)
      return "Arriving now" if eta[:total_seconds]&.zero? || (eta[:minutes].zero? && eta[:seconds].zero?)

      parts = []
      parts << "#{eta[:minutes]} min" if eta[:minutes].positive?
      parts << "#{eta[:seconds]} sec" if eta[:seconds].positive?

      parts.empty? ? "Arriving now" : parts.join(" ")
    end

    # Get stops for a specific bus line in a given direction
    #
    # @param line_id [String] The bus line ID (e.g., "068", "146")
    # @param direction [Integer, String] Direction: 1 (A to B) or 2 (B to A)
    # @return [Hash] The line stops response data
    # @example
    #   client.line_stops('068', 1)
    def line_stops(line_id, direction)
      with_auth_retry do
        url = "/v1/transport/busemtmad/lines/#{line_id}/stops/#{direction}/"

        response = authenticated_connection.get(url)
        parse_response(response)
      end
    end

    # Get formatted stop information for a bus line
    #
    # @param line_id [String] The bus line ID (e.g., "068", "146")
    # @param direction [Integer, String] Direction: 1 (A to B) or 2 (B to A)
    # @return [Array<Hash>] Array of stops with formatted information
    # @example
    #   client.line_stops_info('068', 1)
    #   # => [
    #   #   {
    #   #     stop_id: "1890",
    #   #     name: "CUATRO CAMINOS",
    #   #     address: "Raimundo Fernández Villaverde, 2",
    #   #     coordinates: { lat: 40.4468405647608, lon: -3.7030778919681 },
    #   #     lines: ["068"]
    #   #   },
    #   #   ...
    #   # ]
    def line_stops_info(line_id, direction)
      result = line_stops(line_id, direction)

      return [] unless result["code"] == "00" && result["data"]&.first

      stops = result["data"].first["stops"] || []
      stops.map { |stop| format_stop(stop) }
    end

    # Format a single stop hash into a cleaner structure
    #
    # @param stop [Hash] Raw stop data from API
    # @return [Hash] Formatted stop information
    def self.format_stop(stop)
      coords = stop.dig("geometry", "coordinates") || []
      lines = stop["dataLine"]
      lines = [lines] unless lines.is_a?(Array)

      {
        stop_id: stop["stop"],
        name: stop["name"],
        address: stop["postalAddress"],
        coordinates: {
          lat: coords[1],
          lon: coords[0]
        },
        lines: lines
      }
    end

    # Instance method wrapper for format_stop
    def format_stop(stop)
      self.class.format_stop(stop)
    end

    private

    # Execute a block with automatic re-authentication on 401 errors
    #
    # @yield The block to execute
    # @return The result of the block
    # @raise [Faraday::UnauthorizedError] if re-authentication fails
    def with_auth_retry
      ensure_authenticated!
      yield
    rescue Faraday::UnauthorizedError
      # Token may have expired, re-authenticate and retry once
      reset_authenticated_connection!
      login
      yield
    end

    # Reset the authenticated connection to use the new token
    def reset_authenticated_connection!
      @authenticated_connection = nil
    end

    def seconds_to_eta(total_seconds)
      {
        minutes: total_seconds / 60,
        seconds: total_seconds % 60,
        total_seconds: total_seconds
      }
    end

    def validate_credentials!
      return if @client_id && @pass_key

      raise ConfigurationError,
            "Missing credentials. Provide client_id and pass_key or set EMT_CLIENT_ID and EMT_PASS_KEY environment variables."
    end

    def unauthenticated_connection
      @unauthenticated_connection ||= build_connection
    end

    def authenticated_connection
      @authenticated_connection ||= build_connection do |conn|
        conn.headers["accessToken"] = @access_token
      end
    end

    def build_connection
      Faraday.new(url: BASE_URL) do |conn|
        conn.request :retry, max: 2, interval: 0.5
        conn.response :raise_error
        yield conn if block_given?
      end
    end

    def parse_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ApiError, "Invalid JSON response: #{e.message}"
    end

    def build_arrivals_body(options)
      {
        "cultureInfo" => options.fetch(:culture_info, "ES"),
        "Text_StopRequired_YN" => bool_to_yn(options.fetch(:stop_info, false)),
        "Text_EstimationsRequired_YN" => bool_to_yn(options.fetch(:estimations, true)),
        "Text_IncidencesRequired_YN" => bool_to_yn(options.fetch(:incidents, false)),
        "DateTime_Referenced_Incidencies_YYYYMMDD" => options.fetch(:incidents_date, Time.now.strftime("%Y%m%d"))
      }
    end

    def bool_to_yn(value)
      value ? "Y" : "N"
    end
  end
end
