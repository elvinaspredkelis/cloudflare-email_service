# frozen_string_literal: true

module Cloudflare
  module EmailService
    # Validates and serializes an outbound email into the JSON payload expected
    # by the Cloudflare Email Service "send" endpoint.
    #
    # Addresses may be given as:
    #   * a String — "user@example.com" or "Display Name <user@example.com>"
    #   * a Hash   — { email: "user@example.com", name: "Display Name" }
    #                (:address is accepted as an alias for :email)
    #   * an Array of any of the above (for to / cc / bcc)
    class Message
      attr_reader :from, :to, :cc, :bcc, :reply_to, :subject,
                  :html, :text, :attachments, :headers

      def initialize(from:, to:, subject:, html: nil, text: nil, cc: nil,
                     bcc: nil, reply_to: nil, attachments: nil, headers: nil)
        @from = from
        @to = to
        @cc = cc
        @bcc = bcc
        @reply_to = reply_to
        @subject = subject
        @html = html
        @text = text
        @attachments = attachments
        @headers = headers
      end

      # @return [self]
      # @raise [ValidationError] when the message cannot be sent.
      def validate!
        raise ValidationError, "from is required" if blank?(from)
        raise ValidationError, "to is required" if blank?(to)
        raise ValidationError, "subject is required" if blank?(subject)
        if blank?(html) && blank?(text)
          raise ValidationError, "provide html and/or text body content"
        end

        self
      end

      # @return [Hash] the request body, with nil/empty fields omitted.
      def to_h
        {
          from: normalize_address(from),
          to: normalize_recipients(to),
          subject: subject,
          cc: optional_recipients(cc),
          bcc: optional_recipients(bcc),
          reply_to: optional_address(reply_to),
          html: presence(html),
          text: presence(text),
          headers: presence(headers),
          attachments: optional_attachments(attachments),
        }.compact
      end

      private

      def optional_recipients(value)
        blank?(value) ? nil : normalize_recipients(value)
      end

      def optional_address(value)
        blank?(value) ? nil : normalize_address(value)
      end

      def optional_attachments(value)
        blank?(value) ? nil : value.map { |a| normalize_attachment(a) }
      end

      def presence(value)
        blank?(value) ? nil : value
      end

      def normalize_recipients(value)
        list = value.is_a?(Array) ? value : [value]
        normalized = list.reject { |v| blank?(v) }.map { |v| normalize_address(v) }
        normalized.length == 1 ? normalized.first : normalized
      end

      def normalize_address(value)
        return value if value.is_a?(String)
        raise ValidationError, "unsupported address: #{value.inspect}" unless value.is_a?(Hash)

        email = address_field(value, :email, :address)
        raise ValidationError, "address hash must include an :email value" if blank?(email)

        name = address_field(value, :name)
        name ? "#{name} <#{email}>" : email
      end

      def address_field(hash, *keys)
        keys.each do |key|
          candidate = hash[key] || hash[key.to_s]
          return candidate unless blank?(candidate)
        end
        nil
      end

      def normalize_attachment(att)
        raise ValidationError, "attachment must be a Hash" unless att.is_a?(Hash)

        h = att.transform_keys(&:to_sym)
        raise ValidationError, "attachment requires :content" if blank?(h[:content])
        raise ValidationError, "attachment requires :filename" if blank?(h[:filename])

        out = { content: h[:content], filename: h[:filename] }
        out[:type] = h[:type] if h[:type]
        out[:disposition] = h[:disposition] if h[:disposition]
        out
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
