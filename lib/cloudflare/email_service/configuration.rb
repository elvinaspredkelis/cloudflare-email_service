# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Holds the transport selection, credentials, and connection options used
    # when a client is built without explicit arguments. Defaults are read from
    # the environment.
    class Configuration
      DEFAULT_API_BASE = "https://api.cloudflare.com/client/v4"
      DEFAULT_SMTP_HOST = "smtp.mx.cloudflare.net"
      DEFAULT_SMTP_PORT = 465
      DEFAULT_TIMEOUT = 30

      # @return [Symbol] :rest (default) or :smtp.
      attr_accessor :transport
      # @return [String, nil] Cloudflare account id (CLOUDFLARE_ACCOUNT_ID).
      #   Required for the REST transport; unused by SMTP.
      attr_accessor :account_id
      # @return [String, nil] API token (CLOUDFLARE_API_TOKEN). REST needs the
      #   "Email Sending: Send" scope; SMTP needs "Email Sending: Edit".
      attr_accessor :api_token
      # @return [String] base URL of the Cloudflare REST API.
      attr_accessor :api_base
      # @return [String] SMTP submission host.
      attr_accessor :smtp_host
      # @return [Integer] SMTP submission port (465, implicit TLS).
      attr_accessor :smtp_port
      # @return [Integer] connection-open timeout in seconds.
      attr_accessor :open_timeout
      # @return [Integer] read timeout in seconds.
      attr_accessor :timeout
      # @return [String, nil] HMAC secret used to verify inbound Action Mailbox
      #   requests (CLOUDFLARE_EMAIL_INGRESS_SECRET). Must match the value the
      #   Cloudflare Email Worker signs with.
      attr_accessor :ingress_secret

      # @return [#instrument] receives a "deliver.cloudflare_email_service"
      #   event on each send. Defaults to ActiveSupport::Notifications when it is
      #   loaded, otherwise a no-op. Assign any object with an
      #   `instrument(name, payload) { ... }` method.
      attr_writer :instrumenter

      def initialize
        @transport = ENV.fetch("CLOUDFLARE_EMAIL_TRANSPORT", "rest").to_sym
        @account_id = ENV.fetch("CLOUDFLARE_ACCOUNT_ID", nil)
        @api_token = ENV.fetch("CLOUDFLARE_API_TOKEN", nil)
        @api_base = ENV.fetch("CLOUDFLARE_API_BASE", DEFAULT_API_BASE)
        @smtp_host = ENV.fetch("CLOUDFLARE_SMTP_HOST", DEFAULT_SMTP_HOST)
        @smtp_port = Integer(ENV.fetch("CLOUDFLARE_SMTP_PORT", DEFAULT_SMTP_PORT))
        @open_timeout = DEFAULT_TIMEOUT
        @timeout = DEFAULT_TIMEOUT
        @ingress_secret = ENV.fetch("CLOUDFLARE_EMAIL_INGRESS_SECRET", nil)
      end

      # Resolved on each read (never memoized) until one is set explicitly, so
      # ActiveSupport::Notifications is picked up as soon as it loads — even if
      # an earlier send already resolved the default to the no-op. An explicit
      # assignment always wins.
      def instrumenter
        @instrumenter || default_instrumenter
      end

      private

      def default_instrumenter
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications
        else
          NullInstrumenter
        end
      end
    end
  end
end
