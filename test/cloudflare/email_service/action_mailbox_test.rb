# frozen_string_literal: true

require "test_helper"
require "stringio"

# Lightweight stand-ins so the opt-in ingress defines and exercises its
# controller without dragging in the full Rails / Action Mailbox stack. This
# mirrors how the Rails delivery-adapter test covers logic without booting Rails.
module ActionMailbox
  class BaseController
    class << self
      def skip_forgery_protection; end
      def before_action(*); end
    end

    attr_accessor :request
    attr_reader :head_status

    def head(status)
      @head_status = status
    end
  end

  class InboundEmail
    class << self
      attr_reader :last_raw

      def create_and_extract_message_id!(raw)
        @last_raw = raw
        :ingested
      end

      def reset!
        @last_raw = nil
      end
    end
  end
end

require "cloudflare/email_service/action_mailbox"

class ActionMailboxIngressTest < CFTestCase
  Controller = ActionMailbox::Ingresses::Cloudflare::InboundEmailsController
  FakeRequest = Struct.new(:media_type, :body)

  RAW = "From: a@x.com\r\nTo: b@y.com\r\nSubject: Hi\r\n\r\nHello"

  def setup
    super
    ActionMailbox::InboundEmail.reset!
  end

  def controller_for(raw, media_type: "message/rfc822")
    controller = Controller.new
    controller.request = FakeRequest.new(media_type, raw && StringIO.new(raw))
    controller
  end

  def test_create_ingests_raw_message_and_returns_no_content
    controller = controller_for(RAW)
    controller.create

    assert_equal RAW, ActionMailbox::InboundEmail.last_raw
    assert_equal :no_content, controller.head_status
  end

  def test_create_rejects_empty_body
    controller = controller_for("")
    controller.create

    assert_nil ActionMailbox::InboundEmail.last_raw
    assert_equal :unprocessable_entity, controller.head_status
  end

  def test_create_rejects_missing_body
    controller = controller_for(nil)
    controller.create

    assert_nil ActionMailbox::InboundEmail.last_raw
    assert_equal :unprocessable_entity, controller.head_status
  end

  def test_rejects_non_rfc822_media_type
    controller = controller_for(RAW, media_type: "text/plain")
    controller.send(:require_valid_rfc822_message)

    assert_equal :unsupported_media_type, controller.head_status
  end

  def test_accepts_rfc822_media_type
    controller = controller_for(RAW, media_type: "message/rfc822")

    assert_nil controller.send(:require_valid_rfc822_message)
    assert_nil controller.head_status
  end
end
