# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Fallback instrumenter used when ActiveSupport::Notifications is absent.
    # Mirrors its `instrument(name, payload) { ... }` signature so the two are
    # interchangeable, and simply runs the block.
    module NullInstrumenter
      module_function

      def instrument(_name, payload = {})
        yield payload if block_given?
      end
    end

    # Shared send instrumentation for the REST and SMTP clients. Wraps each
    # delivery in a `"deliver.cloudflare_email_service"` event published through
    # the configured instrumenter (ActiveSupport::Notifications when present,
    # otherwise a no-op).
    #
    # The payload carries the transport and recipient counts — never addresses,
    # subject, or body — plus the response status on success. On failure the
    # block raises through, so an ActiveSupport::Notifications instrumenter
    # records the exception on the event.
    module Instrumentation
      EVENT = "deliver.cloudflare_email_service"

      private

      def instrument_delivery(transport, message)
        payload = {
          transport: transport,
          to: recipient_count(message.to),
          cc: recipient_count(message.cc),
          bcc: recipient_count(message.bcc),
        }
        EmailService.configuration.instrumenter.instrument(EVENT, payload) do
          response = yield
          payload[:status] = response.status
          response
        end
      end

      def recipient_count(value)
        return 0 if value.nil?

        value.is_a?(Array) ? value.length : 1
      end
    end
  end
end
