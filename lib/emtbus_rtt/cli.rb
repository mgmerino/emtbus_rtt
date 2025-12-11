# frozen_string_literal: true

require "optparse"
require_relative "../emtbus_rtt"

module EmtbusRtt
  # Command-line interface for the EMT Madrid API
  class CLI
    COLORS = {
      reset: "\e[0m",
      bold: "\e[1m",
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      blue: "\e[34m",
      cyan: "\e[36m",
      gray: "\e[90m"
    }.freeze

    def initialize(args = ARGV)
      @args = args
      @options = {
        culture_info: "ES",
        stop_info: true,
        estimations: true,
        incidents: false
      }
    end

    def run
      parse_options!

      case @command
      when "arrivals"
        arrivals_command
      when "whoami"
        whoami_command
      else
        puts parser
        exit 1
      end
    rescue EmtbusRtt::Error => e
      error("Error: #{e.message}")
      exit 1
    rescue Faraday::Error => e
      error("HTTP Error: #{e.message}")
      exit 1
    end

    private

    def parse_options!
      parser.parse!(@args)
      @command = @args.shift
    end

    def parser
      @parser ||= OptionParser.new do |opts|
        opts.banner = "Usage: emtbus [options] <command> [arguments]"
        opts.separator ""
        opts.separator "Commands:"
        opts.separator "  arrivals <stop_id> [line]  Get bus arrivals for a stop"
        opts.separator "  whoami                     Check current authentication status"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-l", "--lang LANG", "Language: EN or ES (default: ES)") do |lang|
          @options[:culture_info] = lang.upcase
        end

        opts.on("-i", "--[no-]incidents", "Include incident information") do |v|
          @options[:incidents] = v
        end

        opts.on("--[no-]stop-info", "Include stop information (default: true)") do |v|
          @options[:stop_info] = v
        end

        opts.on("-v", "--version", "Show version") do
          puts "emtbus_rtt #{EmtbusRtt::VERSION}"
          exit
        end

        opts.on("-h", "--help", "Show this help") do
          puts opts
          exit
        end

        opts.separator ""
        opts.separator "Environment Variables:"
        opts.separator "  EMT_CLIENT_ID  Your EMT MobilityLabs client ID"
        opts.separator "  EMT_PASS_KEY   Your EMT MobilityLabs pass key"
        opts.separator ""
        opts.separator "Examples:"
        opts.separator "  emtbus arrivals 3112"
        opts.separator "  emtbus arrivals 3112 146"
        opts.separator "  emtbus arrivals 3112 --lang EN"
        opts.separator "  emtbus whoami"
      end
    end

    def arrivals_command
      stop_id = @args.shift
      line = @args.shift

      unless stop_id
        error("Error: stop_id is required")
        puts parser
        exit 1
      end

      info("Fetching arrivals for stop #{stop_id}#{line ? " (line #{line})" : ""}...")

      client = EmtbusRtt.client
      result = client.arrivals(stop_id, line: line, **@options)

      display_arrivals(result, stop_id)
    end

    def whoami_command
      info("Checking authentication status...")

      client = EmtbusRtt.client
      result = client.whoami

      display_whoami(result)
    end

    def display_arrivals(result, stop_id)
      if result["code"] != "00"
        error("API Error: #{result['description']}")
        return
      end

      data = result["data"]&.first
      unless data
        warning("No data available for stop #{stop_id}")
        return
      end

      arrivals = data["Arrive"] || []

      if arrivals.empty?
        warning("No buses arriving at stop #{stop_id}")
        return
      end

      # Display stop info if available
      stop_info = data["StopInfo"]&.first
      if stop_info && !stop_info.empty?
        header("Stop: #{stop_info['stopName'] || stop_id}")
      else
        header("Stop #{stop_id}")
      end

      puts ""

      # Group by line
      grouped = arrivals.group_by { |a| a["line"] }

      grouped.each do |line_num, line_arrivals|
        destination = line_arrivals.first["destination"]
        line_header("Line #{line_num}", destination)

        line_arrivals.sort_by { |a| a["estimateArrive"] }.each do |arrival|
          display_arrival(arrival)
        end
        puts ""
      end

      # Display incidents if any
      incidents = data["Incident"]
      display_incidents(incidents) if incidents && !incidents.empty?
    end

    def display_arrival(arrival)
      estimate = arrival["estimateArrive"]
      distance = arrival["DistanceBus"]
      bus_id = arrival["bus"]

      time_str = format_time(estimate)
      distance_str = format_distance(distance)

      color = estimate_color(estimate)

      puts "  #{color}#{time_str}#{COLORS[:reset]} #{COLORS[:gray]}(#{distance_str}, Bus ##{bus_id})#{COLORS[:reset]}"
    end

    def display_incidents(incidents)
      return if incidents.is_a?(Hash) && incidents.empty?

      header("Incidents")
      puts ""

      Array(incidents).each do |incident|
        if incident.is_a?(Hash)
          puts "  #{COLORS[:yellow]}⚠#{COLORS[:reset]} #{incident['title'] || incident['description'] || incident.inspect}"
        else
          puts "  #{COLORS[:yellow]}⚠#{COLORS[:reset]} #{incident}"
        end
      end
    end

    def display_whoami(result)
      data = result["data"]&.first

      unless data
        warning("No user data available")
        return
      end

      header("Authentication Status")
      puts ""
      puts "  #{COLORS[:cyan]}User:#{COLORS[:reset]} #{data['userName']}"
      puts "  #{COLORS[:cyan]}Email:#{COLORS[:reset]} #{data['email']}"
      puts "  #{COLORS[:cyan]}Token:#{COLORS[:reset]} #{data['_id']}"

      if data["tokenSecExpiration"]
        puts "  #{COLORS[:cyan]}Token Expires In:#{COLORS[:reset]} #{format_duration(data['tokenSecExpiration'])}"
      end

      if data["apiCounter"]
        counter = data["apiCounter"]
        puts ""
        puts "  #{COLORS[:cyan]}API Usage:#{COLORS[:reset]} #{counter['current']} / #{counter['dailyUse']} daily"
      end
    end

    def format_time(seconds)
      return "Arriving now" if seconds.zero? || seconds.negative?
      return "#{seconds} sec" if seconds < 60

      minutes = seconds / 60
      remaining_seconds = seconds % 60

      if remaining_seconds.zero?
        "#{minutes} min"
      else
        "#{minutes} min #{remaining_seconds} sec"
      end
    end

    def format_distance(meters)
      return "At stop" if meters.zero?
      return "#{meters} m" if meters < 1000

      km = meters / 1000.0
      format("%.1f km", km)
    end

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60

      parts = []
      parts << "#{hours}h" if hours.positive?
      parts << "#{minutes}m" if minutes.positive?
      parts.join(" ")
    end

    def estimate_color(seconds)
      case seconds
      when 0..60
        COLORS[:green]
      when 61..300
        COLORS[:yellow]
      else
        COLORS[:blue]
      end
    end

    def header(text)
      puts "#{COLORS[:bold]}#{COLORS[:cyan]}#{text}#{COLORS[:reset]}"
    end

    def line_header(line, destination)
      puts "#{COLORS[:bold]}#{COLORS[:blue]}#{line}#{COLORS[:reset]} → #{destination}"
    end

    def info(text)
      puts "#{COLORS[:gray]}#{text}#{COLORS[:reset]}"
    end

    def warning(text)
      puts "#{COLORS[:yellow]}#{text}#{COLORS[:reset]}"
    end

    def error(text)
      warn "#{COLORS[:red]}#{text}#{COLORS[:reset]}"
    end
  end
end

