# frozen_string_literal: true

require_relative "lib/emtbus_rtt/version"

Gem::Specification.new do |spec|
  spec.name = "emtbus_rtt"
  spec.version = EmtbusRtt::VERSION
  spec.authors = ["Manuel González"]
  spec.email = ["mgmerino@gmail.com"]

  spec.summary = "Ruby wrapper for EMT Madrid public transport API"
  spec.description = "A Ruby gem for accessing real-time bus arrival information from EMT Madrid MobilityLabs API"
  spec.homepage = "https://github.com/mgmerino/emtbus_rtt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[
                          lib/**/*
                          exe/*
                          web/**/*
                          LICENSE.txt
                          README.md
                          CHANGELOG.md
                        ]).reject { |f| File.directory?(f) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "webrick", "~> 1.8"
end
