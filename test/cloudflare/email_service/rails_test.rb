# frozen_string_literal: true

require "test_helper"
require "mail"
require "cloudflare/email_service/rails"

class RailsAdapterTest < CFTestCase
  Adapter = Cloudflare::EmailService::Rails
  ES = Cloudflare::EmailService

  def multipart_mail
    Mail.new do
      from "Acme <from@example.com>"
      to "to@example.com"
      cc "cc@example.com"
      subject "Hi"
      text_part { body "Hello" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>Hello</p>"
      end
    end
  end

  def test_mapping_extracts_addresses_and_bodies
    mapped = Adapter::MessageMapping.call(multipart_mail)

    assert_equal "Acme <from@example.com>", mapped[:from]
    assert_equal ["to@example.com"], mapped[:to]
    assert_equal ["cc@example.com"], mapped[:cc]
    assert_equal "Hi", mapped[:subject]
    assert_equal "Hello", mapped[:text]
    assert_equal "<p>Hello</p>", mapped[:html]
  end

  def test_mapping_plain_text_only
    mail = Mail.new do
      from "a@x.com"
      to "b@y.com"
      subject "s"
      body "just text"
    end

    mapped = Adapter::MessageMapping.call(mail)
    assert_equal "just text", mapped[:text]
    assert_nil mapped[:html]
  end

  def test_mapping_attachments_base64_encoded
    mail = Mail.new do
      from "a@x.com"
      to "b@y.com"
      subject "s"
      body "hi"
      add_file(filename: "f.txt", content: "file-bytes")
    end

    attachment = Adapter::MessageMapping.call(mail)[:attachments].first
    assert_equal "f.txt", attachment[:filename]
    assert_equal "file-bytes", attachment[:content].unpack1("m")
  end

  def test_mapping_forwards_custom_and_threading_headers
    mail = Mail.new do
      from "a@x.com"
      to "b@y.com"
      subject "s"
      body "hi"
      header["X-Campaign"] = "welcome"
      header["In-Reply-To"] = "<abc@x.com>"
    end

    headers = Adapter::MessageMapping.call(mail)[:headers]
    assert_equal "welcome", headers["X-Campaign"]
    assert_equal "<abc@x.com>", headers["In-Reply-To"]
  end

  def test_delivery_method_maps_and_delegates_to_client
    delivered = []
    fake_client = Object.new
    fake_client.define_singleton_method(:deliver) do |message|
      delivered << message
      :sent
    end

    method = Adapter::DeliveryMethod.new(client: fake_client)
    result = method.deliver!(multipart_mail)

    assert_equal :sent, result
    assert_equal 1, delivered.length
    assert_instance_of ES::Message, delivered.first
    assert_equal "Hi", delivered.first.subject
    assert_equal "<p>Hello</p>", delivered.first.to_h[:html]
  end

  def test_requiring_adapter_without_rails_is_safe
    # No Rails/ActionMailer loaded in the test process; the classes must still
    # be defined and the require must not have raised.
    assert defined?(Adapter::DeliveryMethod)
    assert defined?(Adapter::MessageMapping)
  end
end
