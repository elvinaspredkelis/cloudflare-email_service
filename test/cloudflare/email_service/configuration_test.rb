# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < CFTestCase
  ES = Cloudflare::EmailService

  def test_configure_stores_credentials
    ES.configure do |c|
      c.account_id = "acct_123"
      c.api_token = "tok_abc"
    end

    assert_equal "acct_123", ES.configuration.account_id
    assert_equal "tok_abc", ES.configuration.api_token
  end

  def test_client_built_from_global_configuration
    ES.configure do |c|
      c.account_id = "acct_123"
      c.api_token = "tok_abc"
    end

    client = ES.client
    assert_equal "acct_123", client.account_id
    assert_equal "tok_abc", client.api_token
  end

  def test_client_raises_when_credentials_missing
    assert_raises(ES::ConfigurationError) { ES.client }
  end

  def test_client_defaults_to_rest_transport
    ES.configure do |c|
      c.account_id = "acct_123"
      c.api_token = "tok_abc"
    end

    assert_instance_of ES::Client, ES.client
  end

  def test_client_builds_smtp_transport_when_selected
    ES.configure do |c|
      c.transport = :smtp
      c.api_token = "tok_abc"
    end

    assert_instance_of ES::SMTPClient, ES.client
  end

  def test_client_raises_on_unknown_transport
    ES.configure do |c|
      c.transport = :carrier_pigeon
      c.api_token = "tok_abc"
    end

    assert_raises(ES::ConfigurationError) { ES.client }
  end

  def test_default_instrumenter_is_not_memoized
    config = ES::Configuration.new
    config.instrumenter # resolve the default once

    # The default must never be cached, or a send that happens before
    # ActiveSupport loads would latch the no-op and silently drop later events.
    assert_nil config.instance_variable_get(:@instrumenter)
    assert_respond_to config.instrumenter, :instrument
  end

  def test_explicit_instrumenter_overrides_default
    custom = Object.new
    config = ES::Configuration.new
    config.instrumenter = custom

    assert_same custom, config.instrumenter
  end

  def test_worker_template_path_points_to_shipped_file
    path = ES.worker_template_path
    assert_path_exists path
    assert_includes File.read(path), "X-CF-Email-Signature"
  end
end
