# frozen_string_literal: true

require "test_helper"
require "rails"
require "rails/generators"
require "rails/generators/test_case"
require "generators/cloudflare_email_service/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests CloudflareEmailService::Generators::InstallGenerator
  destination File.expand_path("../../../tmp/generator", __dir__)
  setup :prepare_destination

  def test_namespace_matches_the_documented_command
    assert_equal "cloudflare_email_service:install",
                 CloudflareEmailService::Generators::InstallGenerator.namespace
  end

  def test_creates_initializer_with_configure_block
    run_generator

    assert_file "config/initializers/cloudflare_email_service.rb" do |content|
      assert_match(/Cloudflare::EmailService\.configure do/, content)
      assert_match(/c\.account_id/, content)
      assert_match(/c\.api_token/, content)
      # Inbound bits ship commented out so a send-only install stays minimal.
      assert_match(/# c\.ingress_secret/, content)
      assert_match(%r{# +require "cloudflare/email_service/action_mailbox"}, content)
    end
  end

  def test_prints_next_steps
    output = run_generator
    assert_match(/delivery_method = :cloudflare/, output)
    assert_match(/action_mailbox\.ingress = :cloudflare/, output)
  end
end
