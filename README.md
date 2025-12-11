# EmtbusRtt

A Ruby wrapper for the EMT Madrid MobilityLabs public transport API. Get real-time bus arrival information for Madrid's public bus network.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'emtbus_rtt'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install emtbus_rtt
```

## Prerequisites

You need API credentials from EMT Madrid MobilityLabs:

1. Register at [https://mobilitylabs.emtmadrid.es](https://mobilitylabs.emtmadrid.es)
2. Create an application to get your `X-ClientId` and `passKey`

## Configuration

### Environment Variables (Recommended)

Set these environment variables:

```bash
export EMT_CLIENT_ID="your_client_id"
export EMT_PASS_KEY="your_pass_key"
```

### Programmatic Configuration

```ruby
EmtbusRtt.configure do |config|
  config.client_id = 'your_client_id'
  config.pass_key = 'your_pass_key'
end
```

## Usage

### Ruby API

#### Basic Usage

```ruby
require 'emtbus_rtt'

# Create a client (uses ENV vars or configured credentials)
client = EmtbusRtt.client

# Or with explicit credentials
client = EmtbusRtt::Client.new(
  client_id: 'your_client_id',
  pass_key: 'your_pass_key'
)

# Login (called automatically when needed)
client.login

# Check authentication status
client.whoami

# Get bus arrivals for a stop
arrivals = client.arrivals(3112)

# Get arrivals for a specific line
arrivals = client.arrivals(3112, line: '146')

# With options
arrivals = client.arrivals(3112,
  culture_info: 'EN',      # Language: 'EN' or 'ES'
  stop_info: true,         # Include stop information
  estimations: true,       # Include arrival estimations
  incidents: true,         # Include incident reports
  incidents_date: '20251211'  # Reference date for incidents
)
```

#### Response Structure

The `arrivals` method returns a hash with the API response:

```ruby
{
  "code" => "00",
  "description" => "Data recovered OK",
  "datetime" => "2025-12-11T13:29:50.473789",
  "data" => [
    {
      "Arrive" => [
        {
          "line" => "146",
          "stop" => "3112",
          "destination" => "CALLAO",
          "bus" => 2528,
          "estimateArrive" => 409,  # seconds until arrival
          "DistanceBus" => 1438,    # meters from stop
          "geometry" => {
            "type" => "Point",
            "coordinates" => [-3.1355, 40.2437]
          }
        }
      ],
      "StopInfo" => [...],
      "Incident" => {...}
    }
  ]
}
```

### Command Line Interface

The gem includes a CLI for quick lookups:

```bash
# Get arrivals for a stop
emtbus arrivals 3112

# Get arrivals for a specific line
emtbus arrivals 3112 146

# Use English language
emtbus arrivals 3112 --lang EN

# Include incident information
emtbus arrivals 3112 --incidents

# Check authentication status
emtbus whoami

# Show help
emtbus --help
```

## API Endpoints

### Authentication

#### Login

Authenticates with the API and obtains an access token.

```ruby
client.login
# => { "code" => "00", "data" => [...] }
```

#### Whoami

Returns information about the current authentication.

```ruby
client.whoami
# => { "code" => "02", "data" => [...] }
```

### Bus Information

#### Arrivals

Get real-time arrival information for a bus stop.

```ruby
client.arrivals(stop_id, line: nil, **options)
```

**Parameters:**
- `stop_id` - The bus stop ID (required)
- `line` - Filter by line number (optional, defaults to all lines)

**Options:**
- `:culture_info` - Language code: `'EN'` or `'ES'` (default: `'ES'`)
- `:stop_info` - Include stop information (default: `false`)
- `:estimations` - Include arrival estimations (default: `true`)
- `:incidents` - Include incident reports (default: `false`)
- `:incidents_date` - Reference date for incidents in YYYYMMDD format

## Error Handling

The gem defines several error classes:

```ruby
begin
  client.arrivals(3112)
rescue EmtbusRtt::ConfigurationError => e
  # Missing credentials
rescue EmtbusRtt::AuthenticationError => e
  # Login failed or token invalid
rescue EmtbusRtt::ApiError => e
  # API returned an error
  puts e.code
  puts e.response
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

Data provided by EMT Madrid MobilityLabs. Please mention EMT Madrid MobilityLabs as data source when using this gem.
