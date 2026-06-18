# frozen_string_literal: true

require "openssl"

module Cloudflare
  module EmailService
    # Verifies the HMAC-SHA256 signature a Cloudflare Email Worker attaches to a
    # forwarded inbound message. The Worker signs `"<timestamp>.<raw body>"` with
    # a shared secret and sends the timestamp and hex digest as headers; this
    # recomputes the digest, compares it in constant time, and rejects stale
    # timestamps to block replays.
    #
    # Pure and Rails-free (stdlib OpenSSL only) so it can be unit-tested on its
    # own; the Action Mailbox ingress is a thin wrapper around {.verify}.
    module Inbound
      module_function

      # Reject timestamps more than this many seconds from now (either side).
      REPLAY_WINDOW = 300

      # @return [Symbol] :ok, :stale (timestamp outside the window), or
      #   :bad_signature (missing/empty input or digest mismatch).
      def verify(secret:, timestamp:, signature:, body:, now: Time.now.to_i)
        return :bad_signature if [secret, timestamp, signature, body].any? { |v| v.to_s.empty? }
        return :stale if (now - timestamp.to_i).abs > REPLAY_WINDOW

        # Build the signed payload in binary: raw RFC822 bodies carry bytes > 127
        # (8bit transfer encoding, binary attachments), which would raise
        # Encoding::CompatibilityError if interpolated into a UTF-8 string.
        signed = "#{timestamp}.".b + body.to_s.b
        expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, signed)
        secure_compare(expected, signature.to_s) ? :ok : :bad_signature
      end

      # Constant-time string comparison. Bails early on a length mismatch, which
      # the digest's fixed width makes safe to leak.
      def secure_compare(expected, actual)
        return false unless expected.bytesize == actual.bytesize

        OpenSSL.fixed_length_secure_compare(expected, actual)
      end
    end
  end
end
