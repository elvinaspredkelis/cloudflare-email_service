# frozen_string_literal: true

require "cloudflare/email_service"
require "cloudflare/email_service/inbound"

# Opt-in Action Mailbox ingress: forwards inbound mail from a Cloudflare Email
# Worker into Action Mailbox. Not loaded by the core gem — require it from an
# initializer (inside `Rails.application.config.to_prepare`, so the controller's
# superclass is autoloadable) and select it with
# `config.action_mailbox.ingress = :cloudflare`. The route is registered
# automatically. See the README for setup and the Worker snippet.
if defined?(ActionMailbox)
  module ActionMailbox
    module Ingresses
      module Cloudflare
        # Receives the raw RFC822 message a Cloudflare Email Worker forwards and
        # hands it to Action Mailbox for routing. The Worker signs each request
        # (HMAC-SHA256 over "<timestamp>.<body>"); we verify the signature and
        # reject stale timestamps before accepting the message.
        class InboundEmailsController < ActionMailbox::BaseController
          before_action :verify_signature, :require_valid_rfc822_message

          def create
            if raw_body.empty?
              head :unprocessable_entity
            elsif already_received?
              # Idempotent: a retry re-POSTed a message we already have; don't
              # ingest (and route, and process) it a second time.
              head :no_content
            else
              ActionMailbox::InboundEmail.create_and_extract_message_id!(raw_body)
              head :no_content
            end
          end

          private

          # A Cloudflare/Worker retry can re-deliver the same message within the
          # replay window with a still-valid signature. Skip creating a second
          # InboundEmail when one with this Message-ID already exists, so routing
          # and mailbox processing don't run twice. Messages without a parseable
          # Message-ID can't be deduplicated and always ingest.
          def already_received?
            id = message_id
            return false if id.nil? || id.empty?

            ActionMailbox::InboundEmail.where(message_id: id).exists?
          end

          # The message's Message-ID (without angle brackets), extracted the same
          # way Action Mailbox extracts and stores it. nil when it is absent or
          # the body can't be parsed.
          def message_id
            Mail.from_source(raw_body).message_id
          rescue StandardError
            nil
          end

          def verify_signature
            case ::Cloudflare::EmailService::Inbound.verify(
              secret: signing_secret,
              timestamp: request.headers["X-CF-Email-Timestamp"],
              signature: request.headers["X-CF-Email-Signature"],
              body: raw_body,
            )
            when :ok then nil
            when :stale then head :request_timeout
            else head :unauthorized
            end
          end

          def require_valid_rfc822_message
            return if request.media_type == "message/rfc822"

            head :unsupported_media_type
          end

          # Read once, as binary, so the bytes match exactly what the Worker
          # signed and what Action Mailbox stores. `raw_post` is ActionDispatch's
          # body reader — consistent across Puma, Falcon, and Unicorn, and nil-safe
          # (`request.body` can be nil/non-rewindable on some servers).
          def raw_body
            @raw_body ||= request.raw_post.to_s.b
          end

          # Shared HMAC secret, from the gem configuration
          # (`config.ingress_secret` / CLOUDFLARE_EMAIL_INGRESS_SECRET).
          def signing_secret
            ::Cloudflare::EmailService.configuration.ingress_secret.to_s
          end
        end
      end
    end
  end

  # Register the route so it works like the built-in ingresses. Guarded for
  # non-Rails requires; add the route by hand if your boot order skips this.
  if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
    Rails.application.routes.append do
      post "/rails/action_mailbox/cloudflare/inbound_emails" =>
             "action_mailbox/ingresses/cloudflare/inbound_emails#create",
           as: :rails_cloudflare_inbound_emails
    end
  end
end
