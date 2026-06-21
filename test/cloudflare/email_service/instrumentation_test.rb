# frozen_string_literal: true

require "test_helper"

class InstrumentationTest < CFTestCase
  ES = Cloudflare::EmailService
  URL = "https://api.cloudflare.com/client/v4/accounts/acct/email/sending/send"

  # Records every event it receives; matches the AS::Notifications signature
  # (instrument(name, payload) { ... }) and captures a raised exception.
  class FakeInstrumenter
    attr_reader :events

    def initialize
      @events = []
    end

    def instrument(name, payload = {})
      result = block_given? ? yield(payload) : nil
      @events << { name: name, payload: payload.dup }
      result
    rescue StandardError => e
      @events << { name: name, payload: payload.dup, error: e }
      raise
    end
  end

  def setup
    super
    @instrumenter = FakeInstrumenter.new
    ES.configure do |c|
      c.account_id = "acct"
      c.api_token = "tok"
      c.instrumenter = @instrumenter
    end
  end

  def test_publishes_event_with_payload_on_success
    stub_request(:post, URL).to_return(
      status: 200,
      body: { success: true, result: { delivered: ["b@y.com"] } }.to_json,
    )

    ES.send_email(from: "a@x.com", to: ["b@y.com", "c@z.com"], cc: "d@w.com",
                  subject: "Hi", text: "Hello")

    event = @instrumenter.events.last
    assert_equal "deliver.cloudflare_email_service", event[:name]
    assert_equal :rest, event[:payload][:transport]
    assert_equal 2, event[:payload][:to]
    assert_equal 1, event[:payload][:cc]
    assert_equal 0, event[:payload][:bcc]
    assert_equal 200, event[:payload][:status]
  end

  def test_publishes_event_even_when_send_fails
    stub_request(:post, URL).to_return(status: 500, body: "")

    assert_raises(ES::ServerError) do
      ES.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")
    end

    event = @instrumenter.events.last
    assert_equal "deliver.cloudflare_email_service", event[:name]
    assert_instance_of ES::ServerError, event[:error]
    refute event[:payload].key?(:status)
  end

  def test_does_not_instrument_validation_failures
    assert_raises(ES::ValidationError) do
      ES.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi") # no body
    end

    assert_empty @instrumenter.events
  end

  def test_payload_carries_no_message_content
    stub_request(:post, URL).to_return(
      status: 200, body: { success: true, result: {} }.to_json,
    )

    ES.send_email(from: "a@x.com", to: "b@y.com", subject: "Secret subject",
                  text: "Secret body")

    keys = @instrumenter.events.last[:payload].keys
    assert_equal %i[transport to cc bcc status].sort, keys.sort
  end

  def test_defaults_to_an_instrumenter_responding_to_instrument
    ES.reset_configuration!
    assert_respond_to ES.configuration.instrumenter, :instrument
  end

  # On failure, SMTP events must carry the gem's mapped error (not the raw
  # Net::SMTP* exception), so subscribers classify failures the same way across
  # both transports.
  def test_smtp_failure_event_records_mapped_gem_error
    smtp = ES::SMTPClient.new(api_token: "tok")
    smtp.stub(:transmit, ->(_e) { raise Net::SMTPServerBusy, "451 busy" }) do
      assert_raises(ES::ServerError) do
        smtp.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")
      end
    end

    event = @instrumenter.events.last
    assert_equal "deliver.cloudflare_email_service", event[:name]
    assert_equal :smtp, event[:payload][:transport]
    assert_instance_of ES::ServerError, event[:error]
  end
end
