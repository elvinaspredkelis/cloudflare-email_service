# cloudflare-email_service

[![CI](https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml/badge.svg)](https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml)

A small Ruby client for sending transactional email through the
[Cloudflare Email Service](https://developers.cloudflare.com/email-service/),
over either of two transports:

- **REST** (default) — talks to the send endpoint directly with the Ruby
  standard library (`net/http`). **Zero dependencies.** No Rails, no HTTP gems.

  ```
  POST https://api.cloudflare.com/client/v4/accounts/{account_id}/email/sending/send
  ```

- **SMTP** — submits over `smtp.mx.cloudflare.net:465` (implicit TLS). MIME is
  built with the [`mail`](https://rubygems.org/gems/mail) gem, which is an
  **optional** dependency loaded only when you actually use SMTP.

Same `send_email` call either way — pick the transport in configuration.

## Installation

Add it to your `Gemfile`:

```ruby
gem "cloudflare-email_service"

# Only if you use the SMTP transport:
gem "mail"
```

Then run `bundle install`. Or install directly:

```sh
gem install cloudflare-email_service
```

Requires Ruby 3.1+.

## Credentials

You need a Cloudflare **API token**, plus an **account id** for the REST
transport. Token scope depends on the transport:

| Transport | account id | API token scope        |
| --------- | ---------- | ---------------------- |
| REST      | required   | `Email Sending: Send`  |
| SMTP      | not used   | `Email Sending: Edit`  |

Provide them through the environment:

```sh
export CLOUDFLARE_ACCOUNT_ID="your-account-id"   # REST only
export CLOUDFLARE_API_TOKEN="your-api-token"
export CLOUDFLARE_EMAIL_TRANSPORT="rest"         # or "smtp" (default: rest)
```

or explicitly in code (see below).

## Choosing a transport

The transport is selected once, in configuration; everything else — the
`send_email` call, the returned `Response`, the error classes — is identical.

```ruby
# REST (default) — zero dependencies
Cloudflare::EmailService.configure do |config|
  config.transport  = :rest
  config.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
  config.api_token  = ENV["CLOUDFLARE_API_TOKEN"]
end

# SMTP — requires the `mail` gem
Cloudflare::EmailService.configure do |config|
  config.transport = :smtp
  config.api_token = ENV["CLOUDFLARE_API_TOKEN"] # account_id not needed
end
```

SMTP defaults to `smtp.mx.cloudflare.net:465` (implicit TLS); override with
`config.smtp_host` / `config.smtp_port` if needed. If you select `:smtp` without
the `mail` gem installed, a `ConfigurationError` is raised telling you to add it.

You can also build a transport client directly:

```ruby
Cloudflare::EmailService::Client.new(account_id: "...", api_token: "...")     # REST
Cloudflare::EmailService::SMTPClient.new(api_token: "...")                    # SMTP
```

## Usage

### Global configuration

```ruby
require "cloudflare/email_service"

Cloudflare::EmailService.configure do |config|
  config.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
  config.api_token  = ENV["CLOUDFLARE_API_TOKEN"]
  config.timeout    = 30 # seconds (optional)
end

response = Cloudflare::EmailService.send_email(
  from: "welcome@yourdomain.com",
  to: "recipient@example.com",
  subject: "Welcome!",
  html: "<h1>Welcome</h1><p>Thanks for signing up.</p>",
  text: "Welcome! Thanks for signing up.",
)

response.success?   # => true
response.delivered  # => ["recipient@example.com"]
```

### Explicit client

Skip the global configuration and pass credentials per client — handy when you
send from more than one account:

```ruby
client = Cloudflare::EmailService::Client.new(
  account_id: ENV["CLOUDFLARE_ACCOUNT_ID"],
  api_token: ENV["CLOUDFLARE_API_TOKEN"],
)

client.send_email(
  from: "welcome@yourdomain.com",
  to: "recipient@example.com",
  subject: "Welcome!",
  text: "Thanks for signing up.",
)
```

### Addresses

`from`, `to`, `cc`, `bcc`, and `reply_to` accept:

- a plain string — `"user@example.com"` or `"Display Name <user@example.com>"`
- a hash — `{ email: "user@example.com", name: "Display Name" }`
  (`:address` is accepted as an alias for `:email`)
- `to` / `cc` / `bcc` also accept an array of any of the above

```ruby
Cloudflare::EmailService.send_email(
  from: { email: "welcome@yourdomain.com", name: "Acme" },
  to: ["a@example.com", { email: "b@example.com", name: "B" }],
  cc: "team@yourdomain.com",
  reply_to: "support@yourdomain.com",
  subject: "Hi",
  text: "Hello",
)
```

### Attachments

Attachments are base64-encoded. The total message size (body + attachments)
must not exceed **5 MiB**.

```ruby
require "base64"

Cloudflare::EmailService.send_email(
  from: "reports@yourdomain.com",
  to: "recipient@example.com",
  subject: "Your report",
  text: "See attached.",
  attachments: [
    {
      content: Base64.strict_encode64(File.read("report.pdf")),
      filename: "report.pdf",
      type: "application/pdf",
      disposition: "attachment", # optional
    },
  ],
)
```

### Custom headers

```ruby
Cloudflare::EmailService.send_email(
  from: "a@yourdomain.com",
  to: "b@example.com",
  subject: "Re: thread",
  text: "Reply body",
  headers: { "In-Reply-To" => "<msg-123@yourdomain.com>" },
)
```

## Rails / ActionMailer (optional)

The core gem is Rails-agnostic. Rails integration is **opt-in** and loaded only
when you require it — it registers a `:cloudflare` ActionMailer delivery method
backed by whichever transport you configured.

```ruby
# config/initializers/cloudflare_email_service.rb
require "cloudflare/email_service/rails"

Cloudflare::EmailService.configure do |c|
  c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
  c.api_token  = Rails.application.credentials.dig(:cloudflare, :api_token)
  # c.transport = :smtp   # optional; defaults to :rest
end
```

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :cloudflare
```

Your mailers then send through Cloudflare unchanged:

```ruby
class WelcomeMailer < ApplicationMailer
  def welcome(user)
    mail(from: "welcome@yourdomain.com", to: user.email, subject: "Welcome")
  end
end
```

Prefer ActionMailer's built-in SMTP delivery instead? Point it at Cloudflare
with the provided settings helper — no adapter required:

```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings   = Cloudflare::EmailService.smtp_settings(
  api_token: Rails.application.credentials.dig(:cloudflare, :api_token),
)
```

## Response

`send_email` returns a `Cloudflare::EmailService::Response`:

| Method                | Returns                                            |
| --------------------- | -------------------------------------------------- |
| `#success?`           | `true` when Cloudflare accepted the request        |
| `#delivered`          | array of accepted recipient addresses              |
| `#queued`             | array of queued recipient addresses                |
| `#permanent_bounces`  | array of permanently bounced addresses             |
| `#errors`             | array of Cloudflare error objects                  |
| `#status`             | the HTTP status code                               |
| `#body`               | the raw parsed JSON body                           |

## Errors

Non-2xx responses (and unsuccessful payloads) raise a typed error. All inherit
from `Cloudflare::EmailService::Error`:

| Class                  | When                                          |
| ---------------------- | --------------------------------------------- |
| `ConfigurationError`   | missing `account_id` / `api_token`            |
| `ValidationError`      | the message is missing required fields        |
| `AuthenticationError`  | HTTP 401 / 403                                |
| `RequestError`         | HTTP 400 / 422 and other 4xx                  |
| `RateLimitError`       | HTTP 429                                      |
| `ServerError`          | HTTP 5xx                                      |
| `NetworkError`         | connection failures and timeouts              |

API errors carry extra context:

```ruby
begin
  Cloudflare::EmailService.send_email(...)
rescue Cloudflare::EmailService::APIError => e
  e.status   # => 403
  e.errors   # => [{ "code" => 10000, "message" => "Authentication error" }]
  e.message  # => "[10000] Authentication error"
end
```

## Development

```sh
bundle install
bundle exec rake test     # run the Minitest suite
bundle exec rubocop       # lint
```

## License

Released under the [MIT License](LICENSE.txt).
