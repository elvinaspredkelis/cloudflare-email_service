# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require "cloudflare/email_service"

# Base test case that resets the global configuration before every test.
class CFTestCase < Minitest::Test
  def setup
    Cloudflare::EmailService.reset_configuration!
  end
end
