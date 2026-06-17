# frozen_string_literal: true

require_relative "email_service/version"
require_relative "email_service/errors"
require_relative "email_service/configuration"
require_relative "email_service/message"
require_relative "email_service/response"
require_relative "email_service/client"
require_relative "email_service/smtp_client"

module Cloudflare
  # Send transactional email through the Cloudflare Email Service, over either
  # the REST or the SMTP transport.
  module EmailService
    class << self
      # @return [Configuration] the global default configuration.
      def configuration
        @configuration ||= Configuration.new
      end

      # Yields the global {Configuration} for setup.
      #
      #   Cloudflare::EmailService.configure do |c|
      #     c.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
      #     c.api_token  = ENV["CLOUDFLARE_API_TOKEN"]
      #   end
      #
      # @return [Configuration]
      def configure
        yield configuration if block_given?
        configuration
      end

      # Resets the global configuration. Mainly useful in tests.
      # @return [Configuration]
      def reset_configuration!
        @configuration = Configuration.new
      end

      # Builds the client for the configured transport (:rest or :smtp).
      # @return [Client, SMTPClient]
      def client
        case configuration.transport
        when :rest then Client.new
        when :smtp then SMTPClient.new
        else
          raise ConfigurationError, "unknown transport #{configuration.transport.inspect}"
        end
      end

      # Convenience: build a {Client} from the global config and send.
      # Accepts the same keyword arguments as {Message#initialize}.
      # @return [Response]
      def send_email(**kwargs)
        client.send_email(**kwargs)
      end

      # Cloudflare SMTP submission settings, in the shape both {SMTPClient} and
      # ActionMailer's built-in `:smtp` delivery method expect. Defaults come
      # from the global configuration; pass keywords to override.
      # @return [Hash]
      def smtp_settings(api_token: nil, host: nil, port: nil,
                        open_timeout: nil, timeout: nil)
        config = configuration
        {
          address: host || config.smtp_host,
          port: port || config.smtp_port,
          user_name: SMTPClient::SMTP_USERNAME,
          password: api_token || config.api_token,
          authentication: :plain,
          enable_starttls_auto: false,
          tls: true,
          open_timeout: open_timeout || config.open_timeout,
          read_timeout: timeout || config.timeout,
        }
      end
    end
  end
end
