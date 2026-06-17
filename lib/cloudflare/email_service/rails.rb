# frozen_string_literal: true

require "cloudflare/email_service"

module Cloudflare
  module EmailService
    # Opt-in Rails / ActionMailer integration.
    #
    # This file is NOT loaded by the core gem — require it explicitly (e.g. from
    # an initializer) to register a `:cloudflare` ActionMailer delivery method
    # backed by the configured transport:
    #
    #   # config/initializers/cloudflare_email_service.rb
    #   require "cloudflare/email_service/rails"
    #
    #   Cloudflare::EmailService.configure do |c|
    #     c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
    #     c.api_token  = Rails.application.credentials.dig(:cloudflare, :api_token)
    #   end
    #
    #   # config/environments/production.rb
    #   config.action_mailer.delivery_method = :cloudflare
    module Rails
      # Converts an ActionMailer-built Mail::Message into the keyword arguments
      # accepted by {Message#initialize}.
      module MessageMapping
        module_function

        def call(mail)
          {
            from: single_address(mail[:from]),
            to: address_list(mail[:to]),
            cc: address_list(mail[:cc]),
            bcc: address_list(mail[:bcc]),
            reply_to: single_address(mail[:reply_to]),
            subject: mail.subject,
            text: text_body(mail),
            html: html_body(mail),
            attachments: attachments(mail),
            headers: custom_headers(mail),
          }
        end

        def single_address(field)
          field&.formatted&.first
        end

        def address_list(field)
          field&.formatted
        end

        def text_body(mail)
          return mail.text_part.decoded if mail.text_part
          return nil if mail.multipart? || mail.mime_type == "text/html"

          presence(mail.body.decoded)
        end

        def html_body(mail)
          return mail.html_part.decoded if mail.html_part
          return nil unless mail.mime_type == "text/html"

          presence(mail.body.decoded)
        end

        def presence(string)
          string.nil? || string.empty? ? nil : string
        end

        def attachments(mail)
          return nil if mail.attachments.empty?

          mail.attachments.map do |part|
            {
              content: [part.body.decoded].pack("m0"),
              filename: part.filename,
              type: part.mime_type,
              disposition: part.inline? ? "inline" : "attachment",
            }
          end
        end

        # Forwarded headers: anything custom (X-*) plus threading headers. The
        # structural headers (From/To/Subject/Content-Type/...) are mapped above.
        PASSTHROUGH_HEADERS = %w[in-reply-to references].freeze

        def custom_headers(mail)
          headers = {}
          mail.header.fields.each do |field|
            name = field.name.to_s
            forwardable = name.downcase.start_with?("x-") ||
                          PASSTHROUGH_HEADERS.include?(name.downcase)
            headers[name] = field.value if forwardable
          end
          headers.empty? ? nil : headers
        end
      end

      # ActionMailer delivery method. Credentials and transport come from
      # {Cloudflare::EmailService.configure}; this just maps the message and
      # hands it to the configured transport client. Inject `client:` in
      # settings to override (used in tests).
      class DeliveryMethod
        attr_reader :settings

        def initialize(settings = {})
          @settings = settings || {}
        end

        # @param mail [Mail::Message] the message ActionMailer built.
        # @return [Response]
        def deliver!(mail)
          client.deliver(Message.new(**MessageMapping.call(mail)))
        end

        private

        def client
          @client ||= settings[:client] || EmailService.client
        end
      end
    end
  end
end

# Register the delivery method when ActionMailer is present. Guarded so this
# file is safe to require in a non-Rails process.
if defined?(ActiveSupport)
  ActiveSupport.on_load(:action_mailer) do
    add_delivery_method :cloudflare, Cloudflare::EmailService::Rails::DeliveryMethod
  end
elsif defined?(ActionMailer::Base)
  ActionMailer::Base.add_delivery_method(
    :cloudflare, Cloudflare::EmailService::Rails::DeliveryMethod
  )
end
