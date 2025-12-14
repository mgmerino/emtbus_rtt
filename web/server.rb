# frozen_string_literal: true

require "rack"
require "json"
require_relative "../lib/emtbus_rtt"

module EmtbusRtt
  module Web
    # Simple Rack application to serve the frontend and proxy API requests
    class Server
      PUBLIC_DIR = File.expand_path("public", __dir__)

      def initialize
        @client = nil
        @static = Rack::Files.new(PUBLIC_DIR)
      end

      def call(env)
        request = Rack::Request.new(env)

        case request.path
        when "/api/arrivals"
          handle_arrivals(request)
        when "/api/line_stops"
          handle_line_stops(request)
        else
          serve_static(env)
        end
      rescue StandardError => e
        json_error(e.message, 500)
      end

      private

      def client
        @client ||= EmtbusRtt.client
      end

      def handle_arrivals(request)
        stop_id = request.params["stop_id"]
        line = request.params["line"]

        return json_error("stop_id is required", 400) unless stop_id

        result = client.arrivals(stop_id, line: line, stop_info: true, estimations: true)
        json_response(result)
      end

      def handle_line_stops(request)
        line_id = request.params["line_id"]
        direction = request.params["direction"] || "1"

        return json_error("line_id is required", 400) unless line_id

        result = client.line_stops(line_id, direction)
        json_response(result)
      end

      def serve_static(env)
        # Try to serve the requested file
        path = env["PATH_INFO"]
        path = "/index.html" if path == "/"

        env["PATH_INFO"] = path
        response = @static.call(env)

        # If file not found, serve index.html (SPA fallback)
        if response[0] == 404
          env["PATH_INFO"] = "/index.html"
          response = @static.call(env)
        end

        response
      end

      def json_response(data, status = 200)
        [
          status,
          { "content-type" => "application/json" },
          [data.to_json]
        ]
      end

      def json_error(message, status = 400)
        [
          status,
          { "content-type" => "application/json" },
          [{ error: message }.to_json]
        ]
      end
    end
  end
end
