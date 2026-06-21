# frozen_string_literal: true

# Configure the Cloudflare Email Service client. Credentials can also come from
# the environment (CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN), in which case
# this block is optional.
Cloudflare::EmailService.configure do |c|
  c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
  c.api_token  = Rails.application.credentials.dig(:cloudflare, :api_token)
  # c.transport = :smtp # optional; defaults to :rest (SMTP needs the `mail` gem)

  # Inbound (Action Mailbox) only — must match the Worker's signing secret:
  # c.ingress_secret = Rails.application.credentials.dig(:cloudflare, :ingress_secret)
end

# Inbound (Action Mailbox) only — load the :cloudflare ingress. In `to_prepare`
# so its controller superclass is autoloadable regardless of boot order. Pair it
# with `config.action_mailbox.ingress = :cloudflare` in your environment config.
# Rails.application.config.to_prepare do
#   require "cloudflare/email_service/action_mailbox"
# end
