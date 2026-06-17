# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

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
