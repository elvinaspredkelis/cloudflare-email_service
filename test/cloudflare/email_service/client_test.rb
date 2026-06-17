# frozen_string_literal: true

require "test_helper"

class ClientTest < CFTestCase
  Client = Cloudflare::EmailService::Client
  ES = Cloudflare::EmailService

  ACCOUNT_ID = "acct_123"
  API_TOKEN = "tok_abc"
  URL = "https://api.cloudflare.com/client/v4/accounts/#{ACCOUNT_ID}/email/sending/send".freeze

  def client
    Client.new(account_id: ACCOUNT_ID, api_token: API_TOKEN)
  end

  def success_body(delivered: ["to@example.com"])
    {
      success: true,
      errors: [],
      messages: [],
      result: { delivered: delivered, permanent_bounces: [], queued: [] },
    }.to_json
  end

  def send_basic
    client.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")
  end

  def test_initialize_requires_account_id
    error = assert_raises(ES::ConfigurationError) { Client.new(api_token: API_TOKEN) }
    assert_match(/account_id/, error.message)
  end

  def test_initialize_requires_api_token
    error = assert_raises(ES::ConfigurationError) { Client.new(account_id: ACCOUNT_ID) }
    assert_match(/api_token/, error.message)
  end

  def test_send_email_posts_to_endpoint
    stub = stub_request(:post, URL)
           .with(
             headers: {
               "Authorization" => "Bearer #{API_TOKEN}",
               "Content-Type" => "application/json",
             },
             body: {
               from: "from@example.com",
               to: "to@example.com",
               subject: "Hi",
               text: "Hello",
             },
           )
           .to_return(status: 200, body: success_body,
                      headers: { "Content-Type" => "application/json" })

    response = client.send_email(
      from: "from@example.com",
      to: "to@example.com",
      subject: "Hi",
      text: "Hello",
    )

    assert_requested stub
    assert response.success?
    assert_equal ["to@example.com"], response.delivered
  end

  def test_send_email_raises_authentication_error_on_403
    stub_request(:post, URL).to_return(
      status: 403,
      body: { success: false, errors: [{ code: 10_000, message: "Authentication error" }] }.to_json,
    )

    error = assert_raises(ES::AuthenticationError) { send_basic }
    assert_equal 403, error.status
    assert_match(/Authentication error/, error.message)
  end

  def test_send_email_raises_request_error_on_400
    stub_request(:post, URL).to_return(
      status: 400,
      body: { success: false, errors: [{ message: "Invalid from address" }] }.to_json,
    )

    error = assert_raises(ES::RequestError) { send_basic }
    assert_match(/Invalid from address/, error.message)
  end

  def test_send_email_raises_rate_limit_error_on_429
    stub_request(:post, URL).to_return(status: 429, body: { success: false, errors: [] }.to_json)
    assert_raises(ES::RateLimitError) { send_basic }
  end

  def test_send_email_raises_server_error_on_500
    stub_request(:post, URL).to_return(status: 500, body: "")
    assert_raises(ES::ServerError) { send_basic }
  end

  def test_send_email_raises_network_error_on_connection_failure
    stub_request(:post, URL).to_raise(Errno::ECONNREFUSED)
    assert_raises(ES::NetworkError) { send_basic }
  end

  def test_send_email_validates_before_sending
    assert_raises(ES::ValidationError) do
      client.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi")
    end
  end
end
