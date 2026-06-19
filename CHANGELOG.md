# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- The bundled Email Worker template reads the ingress URL from a
  `CLOUDFLARE_EMAIL_INGRESS_URL` Worker var instead of a hardcoded URL, so it
  deploys unchanged across apps/environments.

## [0.1.0] - 2026-06-18

### Added
- Optional, opt-in Action Mailbox ingress
  (`require "cloudflare/email_service/action_mailbox"`) registering a
  `:cloudflare` ingress at `POST /rails/action_mailbox/cloudflare/inbound_emails`.
  A Cloudflare Email Worker forwards the raw RFC822 message, signed with
  HMAC-SHA256 over `"<timestamp>.<body>"`; the ingress verifies the signature
  (`CLOUDFLARE_EMAIL_INGRESS_SECRET` or the `cloudflare.ingress_secret`
  credential) and rejects stale timestamps to block replays. The core gem stays
  Rails-free; nothing loads unless the ingress is required.
- A ready-to-deploy Cloudflare Email Worker ships with the gem at
  `templates/cloudflare_email_worker.js`; find it locally via
  `Cloudflare::EmailService.worker_template_path`.

### Changed
- Require Ruby 3.2+ (Ruby 3.1 is end-of-life and the Rails 8 integration needs
  3.2.2+).
- The `:cloudflare` ActionMailer delivery method now registers automatically
  via a Railtie inside Rails — no `require "cloudflare/email_service/rails"`
  needed. Set `config.action_mailer.delivery_method = :cloudflare` and go;
  credentials are read from `CLOUDFLARE_ACCOUNT_ID` / `CLOUDFLARE_API_TOKEN`.

### Fixed
- `NetworkError` now also wraps TLS/SSL handshake failures
  (`OpenSSL::SSL::SSLError`) on both transports, matching the documented error
  contract.

## [0.0.1] - 2026-06-17

### Added
- Initial release.
- REST transport: `Cloudflare::EmailService::Client#send_email` sends via
  `POST /accounts/{account_id}/email/sending/send` using only the standard
  library — zero runtime dependencies.
- SMTP transport: `Cloudflare::EmailService::SMTPClient#send_email` submits over
  `smtp.mx.cloudflare.net:465` (implicit TLS). MIME is built with the `mail`
  gem, an optional dependency loaded lazily only when SMTP is used.
- Transport selection via `config.transport = :rest | :smtp`; `send_email`,
  `Response`, and the error classes are identical across transports.
- Optional, opt-in Rails integration (`require "cloudflare/email_service/rails"`)
  registering a `:cloudflare` ActionMailer delivery method. The core gem stays
  Rails-free; nothing Rails-related loads unless the adapter is required.
- `Cloudflare::EmailService.smtp_settings` helper for pointing ActionMailer's
  built-in `:smtp` delivery (or any `mail` client) at Cloudflare.
- Global configuration via `Cloudflare::EmailService.configure` and the
  `Cloudflare::EmailService.send_email` convenience method.
- Address normalization for strings, `{ email:, name: }` hashes, and arrays
  (to / cc / bcc).
- Support for `reply_to`, attachments, and custom headers.
- Typed error classes (`ConfigurationError`, `ValidationError`,
  `AuthenticationError`, `RequestError`, `RateLimitError`, `ServerError`,
  `NetworkError`) and a `Response` wrapper.
