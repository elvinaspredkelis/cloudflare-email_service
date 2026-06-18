# Cloudflare Email Service

A small Ruby client for sending transactional email through the
[Cloudflare Email Service](https://developers.cloudflare.com/email-service/).

Two interchangeable transports: **REST** (default — zero dependencies, just
`net/http`) and **SMTP** (optional, via the [`mail`](https://rubygems.org/gems/mail)
gem). Same `send_email` call either way; pick the transport in configuration.

Developed at [Primevise](https://primevise.com).

<a href="https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/elvinaspredkelis/cloudflare-email_service/actions/workflows/ci.yml/badge.svg"></a>
<a href="https://rubygems.org/gems/cloudflare-email_service"><img alt="Gem Version" src="https://img.shields.io/gem/v/cloudflare-email_service?color=10b981&include_prereleases&logo=ruby&logoColor=f43f5e"></a>
<a href="https://rubygems.org/gems/cloudflare-email_service"><img alt="Gem Downloads" src="https://img.shields.io/gem/dt/cloudflare-email_service?color=10b981&include_prereleases&logo=ruby&logoColor=f43f5e"></a>

---

## Installation

```
bundle add cloudflare-email_service
```

Requires Ruby 3.2+. For the SMTP transport, also add the `mail` gem:

```
bundle add mail
```

---

## Usage

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

`Response` also exposes `#queued`, `#permanent_bounces`, `#errors`, `#status`,
and the raw parsed `#body`.

> [!TIP]
> `from`, `to`, `cc`, `bcc`, and `reply_to` accept a string
> (`"a@x.com"` or `"Display Name <a@x.com>"`), a hash (`{ email:, name: }`), or —
> for `to` / `cc` / `bcc` — an array of either. Add files with
> `attachments: [{ content: Base64.strict_encode64(bytes), filename:, type: }]`
> and arbitrary headers with `headers: { "In-Reply-To" => "<id>" }`.

> [!CAUTION]
> The total message size (body + attachments) must not exceed **5 MiB**.

Skip the global config and pass credentials per client when you send from more
than one account:

```ruby
Cloudflare::EmailService::Client.new(account_id: "...", api_token: "...")  # REST
Cloudflare::EmailService::SMTPClient.new(api_token: "...")                 # SMTP
```

#### Credentials

Set credentials in `configure` (above) or through the environment:

```sh
export CLOUDFLARE_ACCOUNT_ID="your-account-id"   # REST only
export CLOUDFLARE_API_TOKEN="your-api-token"
```

REST needs an `Email Sending: Send` token; SMTP needs `Email Sending: Edit` and
no account id.

---

## Transports

REST is the default and pulls in nothing beyond the standard library. To submit
over SMTP (`smtp.mx.cloudflare.net:465`, implicit TLS) instead, flip one setting:

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
environment. To set them in code (or pick the SMTP transport), add an
initializer:

```ruby
# config/initializers/cloudflare_email_service.rb
Cloudflare::EmailService.configure do |c|
  c.account_id = Rails.application.credentials.dig(:cloudflare, :account_id)
  c.api_token  = Rails.application.credentials.dig(:cloudflare, :api_token)
  # c.transport = :smtp   # optional; defaults to :rest
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

---

## Inbound email (Action Mailbox)

Receive inbound mail through [Action Mailbox](https://guides.rubyonrails.org/action_mailbox_basics.html).
A Cloudflare [Email Worker](https://developers.cloudflare.com/email-routing/email-workers/)
forwards the raw message to a `:cloudflare` ingress that ships with this gem.
Require it (opt-in, like the delivery adapter) and select it:

```ruby
# config/initializers/cloudflare_email_service.rb
require "cloudflare/email_service/action_mailbox"
```

```ruby
# config/environments/production.rb
config.action_mailbox.ingress = :cloudflare
```

Authentication reuses Action Mailbox's standard ingress password — set it in
credentials (`action_mailbox.ingress_password`) or via
`RAILS_INBOUND_EMAIL_PASSWORD`. The route
`POST /rails/action_mailbox/cloudflare/inbound_emails` is registered for you.

Then point an Email Worker at it:

```js
export default {
  async email(message, env) {
    const auth = "Basic " + btoa("actionmailbox:" + env.RAILS_INBOUND_EMAIL_PASSWORD);
    // arrayBuffer (not text) preserves the raw bytes of non-UTF-8 messages.
    const raw = await new Response(message.raw).arrayBuffer();

    const response = await fetch("https://your-app.example.com/rails/action_mailbox/cloudflare/inbound_emails", {
      method: "POST",
      headers: { "Content-Type": "message/rfc822", "Authorization": auth },
      body: raw,
    });

    // Throw on failure so Cloudflare bounces the message rather than silently
    // accepting (and dropping) it.
    if (!response.ok) throw new Error(`ingress error ${response.status}`);
  },
};
```

> [!NOTE]
> The Worker must send `Content-Type: message/rfc822`; the ingress rejects
> anything else with `415 Unsupported Media Type`.

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

API errors also carry `#status` and `#errors` for context.

---

## Development

```sh
bundle exec rake test     # run the Minitest suite
bundle exec rubocop       # lint
```

---

## License

Released under the [MIT License](LICENSE.txt).
