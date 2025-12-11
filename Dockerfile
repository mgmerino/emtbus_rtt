# syntax=docker/dockerfile:1

FROM ruby:3.4-slim

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy dependency files first for layer caching
COPY Gemfile Gemfile.lock emtbus_rtt.gemspec ./
COPY lib/emtbus_rtt/version.rb lib/emtbus_rtt/

# Install dependencies
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Copy the rest of the application
COPY . .

# Expose port
EXPOSE 9292

# Set environment variables
ENV PORT=9292

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9292/ || exit 1

# Install curl for healthcheck
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Run the web server
CMD ["ruby", "exe/emtbus-web"]

