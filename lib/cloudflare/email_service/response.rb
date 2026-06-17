# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Wraps the JSON body returned by the Cloudflare send endpoint.
    class Response
      # @return [Integer] the HTTP status code.
      attr_reader :status
      # @return [Hash] the parsed JSON body.
      attr_reader :body

      def initialize(status:, body:)
        @status = status
        @body = body || {}
      end

      # @return [Boolean] whether Cloudflare reported success.
      def success?
        body["success"] == true
      end

      # @return [Array] Cloudflare error objects, e.g.
      #   [{ "code" => 1001, "message" => "..." }].
      def errors
        body["errors"] || []
      end

      # @return [Array] informational messages from the API.
      def messages
        body["messages"] || []
      end

      # @return [Hash] the "result" object.
      def result
        body["result"] || {}
      end

      # @return [Array<String>] addresses Cloudflare accepted for delivery.
      def delivered
        result["delivered"] || []
      end

      # @return [Array<String>] addresses queued for later delivery.
      def queued
        result["queued"] || []
      end

      # @return [Array<String>] addresses that permanently bounced.
      def permanent_bounces
        result["permanent_bounces"] || []
      end
    end
  end
end
