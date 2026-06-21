# frozen_string_literal: true

require "rails/generators/base"

# Generator-only namespace. The flat constant maps the gem name
# `cloudflare-email_service` onto the `rails g cloudflare_email_service:install`
# command (Rails derives the namespace from the first module). Runtime code
# lives under `Cloudflare::EmailService`; this file is loaded only by Rails'
# generator lookup, never at gem runtime, so the core stays Rails-free.
module CloudflareEmailService
  module Generators
    # Creates the initializer and prints the remaining setup steps.
    #
    #   bin/rails g cloudflare_email_service:install
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create a Cloudflare Email Service initializer and print the setup steps."

      def create_initializer
        template "cloudflare_email_service.rb",
                 "config/initializers/cloudflare_email_service.rb"
      end

      def print_next_steps
        say "\ncloudflare-email_service installed.\n", :green
        say <<~STEPS
          Next steps:

            1. Point ActionMailer at Cloudflare (e.g. config/environments/production.rb):
                 config.action_mailer.delivery_method = :cloudflare

            2. Set credentials — in the initializer just created, or via the
               environment: CLOUDFLARE_ACCOUNT_ID (REST only) and CLOUDFLARE_API_TOKEN.

            3. Inbound mail (Action Mailbox), optional — in the initializer,
               uncomment `ingress_secret` and the `to_prepare` require, then set:
                 config.action_mailbox.ingress = :cloudflare
               and deploy the bundled Worker (find it at
               `Cloudflare::EmailService.worker_template_path`), setting its
               CLOUDFLARE_EMAIL_INGRESS_URL and CLOUDFLARE_EMAIL_INGRESS_SECRET vars.
        STEPS
      end
    end
  end
end
