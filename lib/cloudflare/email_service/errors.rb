# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Base class for every error raised by this gem.
    class Error < StandardError; end

    # Raised when required configuration (account_id / api_token) is missing.
    class ConfigurationError < Error; end

    # Raised when a message is missing required fields before it is sent.
    class ValidationError < Error; end

    # Base class for errors returned by the Cloudflare API.
    class APIError < Error
      # @return [Integer, nil] the HTTP status code.
      attr_reader :status
      # @return [Array] the Cloudflare "errors" array, when present.
      attr_reader :errors
      # @return [Response, nil] the wrapped API response.
      attr_reader :response
      # @return [Integer, nil] seconds to wait before retrying, parsed from the
      #   `Retry-After` response header whenever the API sends one (typically a
      #   429, sometimes a 503). nil when the header is absent or not an integer
      #   number of seconds.
      attr_reader :retry_after

      def initialize(message = nil, status: nil, errors: nil, response: nil, retry_after: nil)
        @status = status
        @errors = errors || []
        @response = response
        @retry_after = retry_after
        super(message)
      end
    end

    # 401 / 403 — missing, invalid, or insufficiently scoped API token.
    class AuthenticationError < APIError; end

    # 400 / 422 and other 4xx — the request was rejected as invalid.
    class RequestError < APIError; end

    # 429 — too many requests.
    class RateLimitError < APIError; end

    # 5xx — Cloudflare-side failure.
    class ServerError < APIError; end

    # Connection refused/reset, timeouts, DNS failures, etc.
    class NetworkError < Error; end
  end
end
