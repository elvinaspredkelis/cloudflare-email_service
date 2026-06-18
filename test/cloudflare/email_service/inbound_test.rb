# frozen_string_literal: true

require "test_helper"
require "cloudflare/email_service/inbound"

class InboundTest < Minitest::Test
  Inbound = Cloudflare::EmailService::Inbound

  SECRET = "ingress-secret"
  BODY = "From: a@x.com\r\nTo: b@y.com\r\nSubject: Hi\r\n\r\nHello"
  NOW = 1_750_000_000

  def signature(timestamp: NOW, body: BODY, secret: SECRET)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  def verify(**overrides)
    defaults = { secret: SECRET, timestamp: NOW, signature: signature, body: BODY, now: NOW }
    Inbound.verify(**defaults, **overrides)
  end

  def test_valid_signature_is_ok
    assert_equal :ok, verify
  end

  def test_wrong_signature_is_rejected
    assert_equal :bad_signature, verify(signature: signature(secret: "other"))
  end

  def test_tampered_body_is_rejected
    assert_equal :bad_signature, verify(body: "#{BODY} tampered")
  end

  def test_old_timestamp_is_stale
    old = NOW - Inbound::REPLAY_WINDOW - 1
    assert_equal :stale, verify(timestamp: old, signature: signature(timestamp: old))
  end

  def test_future_timestamp_is_stale
    future = NOW + Inbound::REPLAY_WINDOW + 1
    assert_equal :stale, verify(timestamp: future, signature: signature(timestamp: future))
  end

  def test_timestamp_at_window_edge_is_ok
    edge = NOW - Inbound::REPLAY_WINDOW
    assert_equal :ok, verify(timestamp: edge, signature: signature(timestamp: edge))
  end

  def test_missing_values_are_rejected
    assert_equal :bad_signature, verify(secret: "")
    assert_equal :bad_signature, verify(signature: "")
    assert_equal :bad_signature, verify(timestamp: nil)
    assert_equal :bad_signature, verify(body: "")
  end
end
