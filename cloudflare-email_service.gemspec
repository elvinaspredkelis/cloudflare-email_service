# frozen_string_literal: true

require_relative "lib/cloudflare/email_service/version"

Gem::Specification.new do |spec|
  spec.name = "cloudflare-email_service"
  spec.version = Cloudflare::EmailService::VERSION
  spec.authors = ["Elvinas Predkelis"]
  spec.email = ["elvinas@trip1.com"]

  spec.summary = "Send and receive email through the Cloudflare Email Service."
  spec.description = "A small Ruby client for the Cloudflare Email Service with " \
                     "zero runtime dependencies and optional Rails integration " \
                     "(ActionMailer delivery and Action Mailbox inbound)."
  spec.homepage = "https://github.com/elvinaspredkelis/cloudflare-email_service"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("lib/**/*.rb") + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ["lib"]

  # `actionmailbox` (with `railties`) boots a real Rails app in the test suite
  # to verify the inbound ingress loads and wires in correctly. Dev-only — the
  # gem itself adds no Rails runtime dependency.
  spec.add_development_dependency "actionmailbox", ">= 7.1"
  # `actionmailer` lets the suite boot a real Rails app and confirm the Railtie
  # auto-registers the :cloudflare delivery method. Dev-only.
  spec.add_development_dependency "actionmailer", ">= 7.1"
  # `mail` is an OPTIONAL runtime dependency: it is required lazily only when
  # the SMTP transport is used. REST stays dependency-free. It is declared here
  # for development so the SMTP transport can be exercised by the test suite.
  spec.add_development_dependency "mail", "~> 2.7"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "railties", ">= 7.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
