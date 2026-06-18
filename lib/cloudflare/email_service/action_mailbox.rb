# frozen_string_literal: true

require "cloudflare/email_service"

# Opt-in Action Mailbox ingress: forwards inbound mail from a Cloudflare Email
# Worker into Action Mailbox. Not loaded by the core gem — require it explicitly
# and select it with `config.action_mailbox.ingress = :cloudflare`. The route is
# registered automatically. See the README for setup and the Worker snippet.
if defined?(ActionMailbox)
  module ActionMailbox
    module Ingresses
      module Cloudflare
        # Receives the raw RFC822 message a Cloudflare Email Worker forwards and
        # hands it to Action Mailbox for routing. Mirrors the built-in `:relay`
        # ingress; the only Cloudflare-specific part is the name and route.
        class InboundEmailsController < ActionMailbox::BaseController
          before_action :authenticate_by_password, :require_valid_rfc822_message

          def create
            raw = request.body&.read
            if raw.nil? || raw.empty?
              head :unprocessable_entity
            else
              ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
              head :no_content
            end
          end

          private

          def require_valid_rfc822_message
            return if request.media_type == "message/rfc822"

            head :unsupported_media_type
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
