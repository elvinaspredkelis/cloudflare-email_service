# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Delivers a {Message} over Cloudflare's SMTP submission endpoint
    # (smtp.mx.cloudflare.net:465, implicit TLS).
    #
    # MIME assembly is delegated to the `mail` gem, which is an *optional*
    # dependency: it is required lazily the first time an SMTP client is built,
    # so the REST transport stays dependency-free.
    #
    #   client = Cloudflare::EmailService::SMTPClient.new(api_token: "...")
    #   client.send_email(from: "a@x.com", to: "b@y.com",
    #                     subject: "Hi", text: "Hello")
    class SMTPClient
      include Instrumentation

      # Cloudflare requires the literal string "api_token" as the SMTP username;
      # the password is the API token itself.
      SMTP_USERNAME = "api_token"

      attr_reader :api_token, :host, :port, :open_timeout, :timeout

      def initialize(api_token: nil, host: nil, port: nil,
                     open_timeout: nil, timeout: nil)
        config = EmailService.configuration
        @api_token = api_token || config.api_token
        @host = host || config.smtp_host
        @port = port || config.smtp_port
        @open_timeout = open_timeout || config.open_timeout
        @timeout = timeout || config.timeout

        raise ConfigurationError, "no api_token configured" if @api_token.to_s.empty?

        load_dependencies!
      end

      # Builds and sends a message. Accepts the same keyword arguments as
      # {Message#initialize}.
      # @return [Response]
      def send_email(**)
        deliver(Message.new(**))
      end

      # Sends a pre-built {Message} over SMTP.
      # @return [Response]
      def deliver(message)
        message.validate!
        instrument_delivery(:smtp, message) do
          envelope = build_envelope(message)
          envelope.delivery_method(:smtp, smtp_settings)
          transmit(envelope)
          accepted(envelope)
        end
      rescue Net::SMTPAuthenticationError => e
        raise AuthenticationError, e.message
      rescue Net::SMTPError => e
        # Every other SMTP protocol error (busy, syntax, fatal, unknown, ...).
        raise ServerError, e.message
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET,
             Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError, IOError,
             OpenSSL::SSL::SSLError => e
        raise NetworkError, "SMTP delivery failed: #{e.class}: #{e.message}"
      end

      private

      def smtp_settings
        EmailService.smtp_settings(
          api_token: api_token, host: host, port: port,
          open_timeout: open_timeout, timeout: timeout
        )
      end

      # Seam for testing: the actual network send lives here on its own.
      def transmit(envelope)
        envelope.deliver!
      end

      def build_envelope(message)
        body = message.to_h
        envelope = Mail.new
        apply_addresses(envelope, body)
        envelope.subject = body[:subject]
        apply_body(envelope, body[:text], body[:html])
        apply_attachments(envelope, body[:attachments])
        apply_headers(envelope, body[:headers])
        envelope
      end

      def apply_addresses(envelope, body)
        envelope.from = body[:from]
        envelope.to = body[:to]
        envelope.cc = body[:cc] if body[:cc]
        envelope.bcc = body[:bcc] if body[:bcc]
        envelope.reply_to = body[:reply_to] if body[:reply_to]
      end

      def apply_body(envelope, text, html)
        if text && html
          envelope.text_part = mime_part("text/plain", text)
          envelope.html_part = mime_part("text/html", html)
        elsif html
          envelope.content_type = "text/html; charset=UTF-8"
          envelope.body = html
        else
          envelope.body = text
        end
      end

      def mime_part(type, content)
        part = Mail::Part.new
        part.content_type = "#{type}; charset=UTF-8"
        part.body = content
        part
      end

      def apply_attachments(envelope, attachments)
        Array(attachments).each do |attachment|
          options = {
            mime_type: attachment[:type],
            # Our attachment content is base64; hand `mail` the raw bytes.
            # unpack1("m") is the stdlib base64 decode (no extra dependency).
            content: attachment[:content].unpack1("m"),
          }
          # Honor :disposition so SMTP matches REST (e.g. "inline" vs "attachment").
          options[:content_disposition] = attachment[:disposition] if attachment[:disposition]
          envelope.attachments[attachment[:filename]] = options
        end
      end

      def apply_headers(envelope, headers)
        (headers || {}).each { |key, value| envelope[key.to_s] = value }
      end

      # SMTP gives no delivery report, so synthesize a Response that mirrors the
      # REST one: every recipient (to + cc + bcc, as bare addresses) is reported
      # accepted for delivery.
      def accepted(envelope)
        Response.new(
          status: 202,
          body: {
            "success" => true,
            "result" => {
              "delivered" => envelope.destinations,
              "queued" => [],
              "permanent_bounces" => [],
            },
          },
        )
      end

      def load_dependencies!
        require "mail"
        require "net/smtp"
        require "openssl"
      rescue LoadError => e
        raise ConfigurationError,
              "the SMTP transport needs the `mail` gem — add `gem \"mail\"` " \
              "to your Gemfile (#{e.message})"
      end
    end
  end
end
