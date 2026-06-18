# frozen_string_literal: true

require "rails/railtie"

module Cloudflare
  module EmailService
    # Registers the `:cloudflare` ActionMailer delivery method automatically
    # inside a Rails app, so adding the gem is enough — no explicit require.
    #
    # Loaded only when Rails is present (see cloudflare/email_service.rb), so the
    # core gem stays Rails-free. Registration is inert until a host opts in with
    # `config.action_mailer.delivery_method = :cloudflare`.
    class Railtie < ::Rails::Railtie
      initializer "cloudflare_email_service.action_mailer",
                  before: "action_mailer.set_configs" do
        ActiveSupport.on_load(:action_mailer) do
          require "cloudflare/email_service/rails"
        end
      end
    end
  end
end
