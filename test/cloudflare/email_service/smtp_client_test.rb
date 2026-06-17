# frozen_string_literal: true

require "test_helper"

class SMTPClientTest < CFTestCase
  SMTPClient = Cloudflare::EmailService::SMTPClient
  Message = Cloudflare::EmailService::Message
  ES = Cloudflare::EmailService

  def client
    SMTPClient.new(api_token: "tok_abc")
  end

  def new_message(**overrides)
    Message.new(from: "from@example.com",
                to: "to@example.com",
                subject: "Hi",
                text: "Hello", **overrides)
  end

  def test_initialize_requires_api_token
    error = assert_raises(ES::ConfigurationError) { SMTPClient.new(api_token: nil) }
    assert_match(/api_token/, error.message)
  end

  def test_smtp_settings_target_cloudflare
    settings = client.send(:smtp_settings)

    assert_equal "smtp.mx.cloudflare.net", settings[:address]
    assert_equal 465, settings[:port]
    assert_equal "api_token", settings[:user_name]
    assert_equal "tok_abc", settings[:password]
    assert settings[:tls]
    refute settings[:enable_starttls_auto]
  end

  def test_build_envelope_sets_fields_and_multipart_body
    envelope = client.send(:build_envelope, new_message(
                                              html: "<p>Hi</p>",
                                              cc: "cc@example.com",
                                              reply_to: "r@example.com",
                                              headers: { "X-Tag" => "welcome" },
                                            ))

    assert_equal ["from@example.com"], envelope.from
    assert_equal ["to@example.com"], envelope.to
    assert_equal ["cc@example.com"], envelope.cc
    assert_equal ["r@example.com"], envelope.reply_to
    assert_equal "Hi", envelope.subject
    assert envelope.multipart?
    assert_equal "Hello", envelope.text_part.body.decoded
    assert_equal "<p>Hi</p>", envelope.html_part.body.decoded
    assert_equal "welcome", envelope["X-Tag"].value
  end

  def test_build_envelope_decodes_attachments
    envelope = client.send(:build_envelope, new_message(attachments: [{
                                                          content: ["file-bytes"].pack("m0"),
                                                          filename: "f.txt",
                                                          type: "text/plain",
                                                        }]))

    attachment = envelope.attachments.first
    assert_equal "f.txt", attachment.filename
    assert_equal "file-bytes", attachment.decoded
  end

  def test_build_envelope_honors_attachment_disposition
    envelope = client.send(:build_envelope, new_message(attachments: [{
                                                          content: ["x"].pack("m0"),
                                                          filename: "logo.png",
                                                          type: "image/png",
                                                          disposition: "inline",
                                                        }]))

    # `mail` lists only `attachment`-disposition parts under #attachments, so
    # assert on the rendered MIME that the inline disposition was applied.
    assert_match(/content-disposition:\s*inline/i, envelope.to_s)
  end

  def test_send_email_reports_bare_recipient_addresses
    smtp = client
    smtp.stub(:transmit, ->(_envelope) {}) do
      response = smtp.send_email(
        from: "a@x.com",
        to: { email: "b@y.com", name: "Bob" },
        cc: "c@z.com",
        subject: "Hi",
        text: "Hello",
      )

      assert_equal ["b@y.com", "c@z.com"], response.delivered
    end
  end

  def test_send_email_returns_success_response
    smtp = client
    smtp.stub(:transmit, ->(_envelope) {}) do
      response = smtp.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")

      assert response.success?
      assert_equal ["b@y.com"], response.delivered
    end
  end

  def test_send_email_maps_authentication_error
    smtp = client
    smtp.stub(:transmit, ->(_e) { raise Net::SMTPAuthenticationError, "535 bad creds" }) do
      assert_raises(ES::AuthenticationError) { send_basic(smtp) }
    end
  end

  def test_send_email_maps_server_error
    smtp = client
    smtp.stub(:transmit, ->(_e) { raise Net::SMTPServerBusy, "451 busy" }) do
      assert_raises(ES::ServerError) { send_basic(smtp) }
    end
  end

  def test_send_email_maps_network_error
    smtp = client
    smtp.stub(:transmit, ->(_e) { raise Errno::ECONNREFUSED }) do
      assert_raises(ES::NetworkError) { send_basic(smtp) }
    end
  end

  def test_send_email_maps_tls_error_to_network_error
    smtp = client
    smtp.stub(:transmit, ->(_e) { raise OpenSSL::SSL::SSLError, "handshake failure" }) do
      assert_raises(ES::NetworkError) { send_basic(smtp) }
    end
  end

  def test_send_email_validates_before_sending
    assert_raises(ES::ValidationError) do
      client.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi")
    end
  end

  private

  def send_basic(smtp)
    smtp.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")
  end
end
