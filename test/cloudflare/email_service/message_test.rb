# frozen_string_literal: true

require "test_helper"

class MessageTest < CFTestCase
  Message = Cloudflare::EmailService::Message
  ValidationError = Cloudflare::EmailService::ValidationError

  def build(**overrides)
    Message.new(
      from: "from@example.com",
      to: "to@example.com",
      subject: "Hi",
      text: "Hello",
      **overrides,
    )
  end

  def test_validate_passes_with_required_fields
    assert_instance_of Message, build.validate!
  end

  def test_validate_requires_from
    error = assert_raises(ValidationError) { build(from: nil).validate! }
    assert_match(/from/, error.message)
  end

  def test_validate_requires_to
    error = assert_raises(ValidationError) { build(to: "").validate! }
    assert_match(/to/, error.message)
  end

  def test_validate_requires_subject
    error = assert_raises(ValidationError) { build(subject: nil).validate! }
    assert_match(/subject/, error.message)
  end

  def test_validate_requires_content
    error = assert_raises(ValidationError) { build(text: nil, html: nil).validate! }
    assert_match(/html.*text/, error.message)
  end

  def test_to_h_omits_empty_optional_fields
    assert_equal({
                   from: "from@example.com",
                   to: "to@example.com",
                   subject: "Hi",
                   text: "Hello",
                 }, build.to_h)
  end

  def test_to_h_includes_optional_fields
    body = build(
      html: "<p>Hello</p>",
      cc: "cc@example.com",
      bcc: %w[b1@example.com b2@example.com],
      reply_to: "reply@example.com",
      headers: { "X-Tag" => "welcome" },
    ).to_h

    assert_equal "<p>Hello</p>", body[:html]
    assert_equal "cc@example.com", body[:cc]
    assert_equal %w[b1@example.com b2@example.com], body[:bcc]
    assert_equal "reply@example.com", body[:reply_to]
    assert_equal({ "X-Tag" => "welcome" }, body[:headers])
  end

  def test_to_h_formats_hash_address
    body = build(from: { email: "from@example.com", name: "Acme" }).to_h
    assert_equal "Acme <from@example.com>", body[:from]
  end

  def test_to_h_accepts_address_alias
    body = build(to: { address: "to@example.com" }).to_h
    assert_equal "to@example.com", body[:to]
  end

  def test_to_h_collapses_single_recipient_array
    assert_equal "to@example.com", build(to: ["to@example.com"]).to_h[:to]
  end

  def test_to_h_normalizes_attachments_and_drops_unknown_keys
    body = build(attachments: [{
                   content: "Zm9v",
                   filename: "f.txt",
                   type: "text/plain",
                   disposition: "attachment",
                   ignored: "x",
                 }]).to_h

    assert_equal([{
                   content: "Zm9v",
                   filename: "f.txt",
                   type: "text/plain",
                   disposition: "attachment",
                 }], body[:attachments])
  end

  def test_to_h_rejects_attachment_without_content
    error = assert_raises(ValidationError) { build(attachments: [{ filename: "f.txt" }]).to_h }
    assert_match(/content/, error.message)
  end
end
