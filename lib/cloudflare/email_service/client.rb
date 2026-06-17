# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "uri"

module Cloudflare
  module EmailService
    # HTTP client for the Cloudflare Email Service send endpoint.
    #
    #   client = Cloudflare::EmailService::Client.new(
    #     account_id: "...", api_token: "..."
    #   )
    #   client.send_email(from: "a@x.com", to: "b@y.com",
    #                     subject: "Hi", text: "Hello")
    class Client
      attr_reader :account_id, :api_token, :api_base, :open_timeout, :timeout

      def initialize(account_id: nil, api_token: nil, api_base: nil,
                     open_timeout: nil, timeout: nil)
        config = EmailService.configuration
        @account_id = account_id || config.account_id
        @api_token = api_token || config.api_token
        @api_base = api_base || config.api_base
        @open_timeout = open_timeout || config.open_timeout
        @timeout = timeout || config.timeout

        raise ConfigurationError, "no account_id configured" if @account_id.to_s.empty?
        raise ConfigurationError, "no api_token configured" if @api_token.to_s.empty?
      end

      # Builds and sends a message. Accepts the same keyword arguments as
      # {Message#initialize}.
      # @return [Response]
      def send_email(**kwargs)
        deliver(Message.new(**kwargs))
      end

      # Sends a pre-built {Message}.
      # @return [Response]
      def deliver(message)
        post(send_uri, message.validate!.to_h)
      end

      private

      def send_uri
        URI("#{api_base}/accounts/#{account_id}/email/sending/send")
      end

      def post(uri, payload)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_token}"
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request["User-Agent"] = "cloudflare-email_service/#{VERSION} (ruby)"
        request.body = JSON.generate(payload)

        handle(http(uri).request(request))
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET,
             Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError, IOError,
             OpenSSL::SSL::SSLError => e
        raise NetworkError, "request failed: #{e.class}: #{e.message}"
      end

      def http(uri)
        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl = uri.scheme == "https"
        client.open_timeout = open_timeout
        client.read_timeout = timeout
        client
      end

      def handle(http_response)
        status = http_response.code.to_i
        response = Response.new(status: status, body: parse(http_response.body))
        return response if status.between?(200, 299) && response.success?

        raise_error(status, response)
      end

      def parse(raw)
        return {} if raw.nil? || raw.empty?

        JSON.parse(raw)
      rescue JSON::ParserError
        { "success" => false, "errors" => [{ "message" => "non-JSON response body" }] }
      end

      def raise_error(status, response)
        raise error_class_for(status).new(
          summarize(response.errors),
          status: status,
          errors: response.errors,
          response: response,
        )
      end

      def error_class_for(status)
        case status
        when 401, 403 then AuthenticationError
        when 429 then RateLimitError
        when 500..599 then ServerError
        else RequestError
        end
      end

      # Collapses the Cloudflare "errors" array into a single human-readable line,
      # prefixing each entry with its numeric code when one is present.
      def summarize(errors)
        lines = Array(errors).filter_map { |entry| describe_error(entry) }
        lines.empty? ? "Cloudflare rejected the request" : lines.join(" | ")
      end

      def describe_error(entry)
        return entry.to_s.empty? ? nil : entry.to_s unless entry.is_a?(Hash)

        code = entry["code"]
        text = entry["message"].to_s
        return nil if text.empty? && code.nil?

        code ? "[#{code}] #{text}".strip : text
      end
    end
  end
end
