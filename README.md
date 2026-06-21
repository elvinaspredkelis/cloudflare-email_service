# Cloudflare Email Service

A small Ruby client for the [Cloudflare Email Service](https://developers.cloudflare.com/email-service/):
send transactional email from any Ruby app, and — in Rails — receive it through
Action Mailbox.

Sending uses one of two interchangeable transports: **REST** (the default — zero
dependencies, just `net/http`) or **SMTP** (optional, via the
[`mail`](https://rubygems.org/gems/mail) gem). The same `send_email` call works
for both.

Battle-tested at [Rinkta](https://rinkta.com). Developed at [Primevise](https://primevise.com).

<a href="https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml/badge.svg"></a>
<a href="https://rubygems.org/gems/cloudflare-email_service"><img alt="Gem Version" src="https://img.shields.io/gem/v/cloudflare-email_service?color=10b981&include_prereleases&logo=ruby&logoColor=f43f5e"></a>
<a href="https://rubygems.org/gems/cloudflare-email_service"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/cloudflare-email_service?color=10b981&include_prereleases&logo=ruby&logoColor=f43f5e"></a>

---

## Installation

```sh
bundle add cloudflare-email_service
```

Requires Ruby 3.2+. For the SMTP transport, also add the `mail` gem:

```sh
bundle add mail
```

---

## Quick start

Configure once with your Cloudflare API token (plus an account id for REST),
then send:

```ruby
require "cloudflare/email_service"

Cloudflare::EmailService.configure do |config|
  config.account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
  config.api_token  = ENV["CLOUDFLARE_API_TOKEN"]
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

Need to send from more than one account? Skip the global config and build a
client directly:

```ruby
Cloudflare::EmailService::Client.new(account_id: "...", api_token: "...")  # REST
Cloudflare::EmailService::SMTPClient.new(api_token: "...")                 # SMTP
```

### Credentials

Set credentials in `configure` (above) or through the environment:

```sh
export CLOUDFLARE_ACCOUNT_ID="your-account-id"   # REST only
export CLOUDFLARE_API_TOKEN="your-api-token"
```

REST needs an `Email Sending: Send` token; SMTP needs `Email Sending: Edit` and
no account id.

---

## Messages

`send_email` accepts these keywords (`from`, `to`, `subject`, and one of
`html` / `text` are required):

| Keyword | Description |
| ------- | ----------- |
| `from` | Sender. A string or `{ email:, name: }` hash. |
| `to` / `cc` / `bcc` | Recipients. A string, a hash, or an array of either. |
| `reply_to` | Reply-To address (string or hash). |
| `subject` | Subject line. |
| `html` / `text` | Body. Provide either or both. |
| `attachments` | Array of `{ content:, filename:, type:, disposition: }`. |
| `headers` | Hash of custom headers, e.g. `{ "In-Reply-To" => "<id>" }`. |

In an address hash, `:address` aliases `:email`. Attachment `content` is Base64:

```ruby
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

> [!CAUTION]
> The total message size (body + attachments) must not exceed **5 MiB**.

---

## Transports

Both transports accept the same `send_email` call and return the same
[`Response`](#response) — they differ only in how the message reaches Cloudflare.
Choose one with `config.transport`.

**REST** (`:rest`, the default) posts JSON to the Cloudflare API over HTTPS
using only `net/http` from the standard library — no MIME assembly, no gems.
Needs an `account_id` and an `Email Sending: Send` token. The right default for
almost everything.

**SMTP** (`:smtp`) submits over `smtp.mx.cloudflare.net:465` (implicit TLS), with
MIME built by the [`mail`](https://rubygems.org/gems/mail) gem — loaded lazily,
only when this transport is used. Needs an `Email Sending: Edit` token and no
account id. Reach for it when your environment already speaks SMTP or only
allows SMTP egress.

```ruby
Cloudflare::EmailService.configure do |config|
  config.transport = :smtp           # default: :rest
  config.api_token = ENV["CLOUDFLARE_API_TOKEN"]
end
```

> [!NOTE]
> Selecting `:smtp` without the `mail` gem installed raises a
> `ConfigurationError` telling you to add it.

---

## Rails

Adding the gem registers a `:cloudflare` delivery method automatically — just
point ActionMailer at it. No require, no initializer:

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :cloudflare
```

Credentials come from `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN` in the
environment. To set them in code, choose the SMTP transport, or receive inbound
mail, use a single initializer:

```ruby
# config/initializers/cloudflare_email_service.rb
Cloudflare::EmailService.configure do |c|
  c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
  c.api_token  = Rails.application.credentials.dig(:cloudflare, :api_token)
  # c.transport = :smtp   # optional; defaults to :rest

  # Inbound (Action Mailbox) only — must match the Worker's signing secret:
  c.ingress_secret = Rails.application.credentials.dig(:cloudflare, :ingress_secret)
end

# Inbound (Action Mailbox) only — load the :cloudflare ingress. In `to_prepare`
# so its controller superclass is autoloadable regardless of boot order.
Rails.application.config.to_prepare do
  require "cloudflare/email_service/action_mailbox"
end
```

Your mailers then send through Cloudflare unchanged. Prefer ActionMailer's
built-in `:smtp` delivery? Point it at Cloudflare with the settings helper:

```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings   = Cloudflare::EmailService.smtp_settings(
  api_token: Rails.application.credentials.dig(:cloudflare, :api_token),
)
```

### Inbound email (Action Mailbox)

Receive mail too. Cloudflare delivers inbound mail to an app only through an
[Email Worker](https://developers.cloudflare.com/email-routing/email-workers/),
so first enable
[Email Routing](https://developers.cloudflare.com/email-service/get-started/route-emails/)
on your domain (it adds the MX/SPF/DKIM records). Then a Worker forwards each
message to a `:cloudflare`
[Action Mailbox](https://guides.rubyonrails.org/action_mailbox_basics.html)
ingress that ships with the gem. The initializer above loads the ingress and
sets the signing secret; then:

**1. Select the ingress:**

```ruby
# config/environments/production.rb
config.action_mailbox.ingress = :cloudflare
```

The route `POST /rails/action_mailbox/cloudflare/inbound_emails` is registered
for you, and every request is verified by an HMAC-SHA256 signature with replay
protection. The ingress reads the body via `request.raw_post`, so it works under
any Rack server — Puma, Falcon, or Unicorn.

**2. Deploy an Email Worker** that signs and forwards each message, and bind it
to an Email Routing rule (or catch-all). One ships with the gem — deploy it
unchanged and set two Worker vars: `CLOUDFLARE_EMAIL_INGRESS_URL` (the route
above) and `CLOUDFLARE_EMAIL_INGRESS_SECRET` (matching the app):

- In this repo: [`templates/cloudflare_email_worker.js`](templates/cloudflare_email_worker.js)
- From the installed gem: `Cloudflare::EmailService.worker_template_path`

Visiting the worker's URL returns a `{ ok, configured }` health check — a quick
way to confirm it's deployed and both vars are set.

> [!NOTE]
> The Worker sends `Content-Type: message/rfc822`; the ingress rejects anything
> else with `415 Unsupported Media Type`.

---

## Response

`send_email` returns a `Cloudflare::EmailService::Response`:

| Method               | Returns                                       |
| -------------------- | --------------------------------------------- |
| `#success?`          | `true` when Cloudflare accepted the request   |
| `#delivered`         | array of accepted recipient addresses         |
| `#queued`            | array of queued recipient addresses           |
| `#permanent_bounces` | array of permanently bounced addresses        |
| `#errors`            | array of Cloudflare error objects             |
| `#status`            | HTTP status code                              |
| `#body`              | the raw parsed JSON body                      |

---

## Errors

Non-2xx responses (and unsuccessful payloads) raise a typed error — every one a
subclass of `Cloudflare::EmailService::Error`:

| Class                 | When                                       |
| --------------------- | ------------------------------------------ |
| `ConfigurationError`  | missing `account_id` / `api_token`         |
| `ValidationError`     | the message is missing required fields     |
| `AuthenticationError` | HTTP 401 / 403                             |
| `RequestError`        | HTTP 400 / 422 and other 4xx               |
| `RateLimitError`      | HTTP 429                                    |
| `ServerError`         | HTTP 5xx                                    |
| `NetworkError`        | connection, timeout, and TLS failures      |

The API errors (`AuthenticationError`, `RequestError`, `RateLimitError`,
`ServerError`) inherit from `APIError` and carry `#status` and `#errors`:

```ruby
begin
  Cloudflare::EmailService.send_email(from: "a@x.com", to: "b@y.com", subject: "Hi", text: "Hello")
rescue Cloudflare::EmailService::APIError => e
  e.status   # => 403
  e.errors   # => [{ "code" => 10000, "message" => "Authentication error" }]
  e.message  # => "[10000] Authentication error"
end
```

---

## Retries

This client doesn't retry a failed send — like the official Resend, Postmark,
Mailgun, and MailPace gems, it raises and leaves the retry policy to you.
Cloudflare already retries _accepted_ mail server-side (soft bounces, with
exponential backoff); retries here are only about getting the request accepted
in the first place.

In Rails, the idiomatic place is the delivery job: send with `deliver_later` and
let Active Job retry the transient failures with backoff, while permanent ones
fail fast. `retry_on` is an Active Job method, so it goes on the delivery job —
not on the mailer:

```ruby
# app/jobs/cloudflare_mail_delivery_job.rb
class CloudflareMailDeliveryJob < ActionMailer::MailDeliveryJob
  retry_on Cloudflare::EmailService::RateLimitError, # 429
           Cloudflare::EmailService::ServerError,    # 5xx
           Cloudflare::EmailService::NetworkError,   # timeout, connection reset, TLS
           wait: :polynomially_longer, attempts: 5
end

# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  self.delivery_job = CloudflareMailDeliveryJob
end
```

On a `429`, Cloudflare may send a `Retry-After` header. When present it's parsed
to an integer number of seconds and exposed as `RateLimitError#retry_after`, so
you can honor the backoff precisely:

```ruby
rescue Cloudflare::EmailService::RateLimitError => e
  e.retry_after   # => 30 (seconds), or nil when not provided
end
```

---

## Instrumentation

Every send publishes a `deliver.cloudflare_email_service` event. When
`ActiveSupport::Notifications` is loaded (e.g. in Rails) it's used
automatically — subscribe to log, time, or meter your sends:

```ruby
ActiveSupport::Notifications.subscribe("deliver.cloudflare_email_service") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info(
    "cloudflare email: transport=#{event.payload[:transport]} " \
    "to=#{event.payload[:to]} status=#{event.payload[:status]} " \
    "duration=#{event.duration.round}ms",
  )
end
```

The payload carries `:transport` (`:rest` / `:smtp`), recipient counts (`:to`,
`:cc`, `:bcc`), and `:status` on success — never addresses, subject, or body. A
failed send raises through, so the event records the exception (and the send
still raises to your caller).

Outside Rails, plug in any object with an `instrument(name, payload) { ... }`
method (the same shape as `ActiveSupport::Notifications`):

```ruby
Cloudflare::EmailService.configure do |c|
  c.instrumenter = MyInstrumenter
end
```

---

## Development

```sh
bundle install            # install dependencies
bundle exec rake test     # run the Minitest suite
bundle exec rubocop       # lint
```

---

## Contributing

Bug reports and pull requests welcome on
[GitHub](https://github.com/elvinaspredkelis/cloudflare-email_service).

---

## License

Released under the [MIT License](LICENSE.txt).
