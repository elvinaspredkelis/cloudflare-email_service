# frozen_string_literal: true

require_relative "lib/cloudflare/email_service/version"

Gem::Specification.new do |spec|
  spec.name = "cloudflare-email_service"
  spec.version = Cloudflare::EmailService::VERSION
  spec.authors = ["Elvinas Predkelis"]
  spec.email = ["elvinas@trip1.com"]

  spec.summary = "Send email through the Cloudflare Email Service (REST or SMTP)."
  spec.description = "A small Ruby client for sending transactional email via " \
                     "the Cloudflare Email Service. The REST transport is " \
                     "dependency-free; the optional SMTP transport uses the " \
                     "`mail` gem only when selected."
  spec.homepage = "https://github.com/elvinaspredkelis/cloudflare-email_service"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("lib/**/*.rb") + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ["lib"]

  # `mail` is an OPTIONAL runtime dependency: it is required lazily only when
  # the SMTP transport is used. REST stays dependency-free. It is declared here
  # for development so the SMTP transport can be exercised by the test suite.
  spec.add_development_dependency "mail", "~> 2.7"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
