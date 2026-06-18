# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "logger"

require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "active_job/railtie"
require "action_mailbox/engine"

# Satisfies ActiveRecord's lazy database-config parse if the model is ever
# referenced; no connection is opened in these tests.
ENV["DATABASE_URL"] ||= "sqlite3::memory:"

# Boot a minimal real Rails app with Action Mailbox so we can verify the gem
# loads and wires itself in exactly as it would inside a host application —
# without a database or a running HTTP server.
class CloudflareIngressTestApp < Rails::Application
  config.eager_load = false
  config.secret_key_base = "test"
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear
  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    "test" => { "service" => "Disk", "root" => Dir.mktmpdir },
  }
  config.action_mailbox.ingress = :cloudflare

  # Load the ingress the way a host app would: from an initializer, after the
  # framework is up and before routes are drawn, so the appended route is live.
  config.after_initialize do
    require "cloudflare/email_service/action_mailbox"
    Rails.application.reload_routes!
  end
end
CloudflareIngressTestApp.initialize!

class ActionMailboxIngressTest < Minitest::Test
  Controller = ActionMailbox::Ingresses::Cloudflare::InboundEmailsController

  def test_controller_loads_and_subclasses_base_controller
    assert_operator Controller, :<, ActionMailbox::BaseController
  end

  def test_route_is_registered
    route = Rails.application.routes.recognize_path(
      "/rails/action_mailbox/cloudflare/inbound_emails", method: :post
    )
    assert_equal "action_mailbox/ingresses/cloudflare/inbound_emails", route[:controller]
    assert_equal "create", route[:action]
  end

  def test_ingress_name_matches_configured_ingress
    name = Controller.new.send(:ingress_name)
    assert_equal :cloudflare, name
    assert_equal ActionMailbox.ingress, name
  end

  def test_password_auth_and_media_type_filters_are_wired
    filters = Controller._process_action_callbacks.map(&:filter)
    assert_includes filters, :authenticate_by_password
    assert_includes filters, :require_valid_rfc822_message
  end

  def test_create_ingests_raw_message_and_heads_no_content
    # Swap a fake in for the DB-backed model so the ingest path needs no
    # database; the real model is autoload-pending and unreferenced until now.
    fake = Class.new do
      class << self
        attr_reader :raw

        def create_and_extract_message_id!(raw)
          @raw = raw
        end
      end
    end
    ActionMailbox.const_set(:InboundEmail, fake)

    controller, statuses = controller_for("From: a@x.com\r\n\r\nHi")
    controller.create

    assert_equal "From: a@x.com\r\n\r\nHi", fake.raw
    assert_equal [:no_content], statuses
  ensure
    ActionMailbox.send(:remove_const, :InboundEmail)
  end

  def test_create_rejects_empty_body
    controller, statuses = controller_for("")
    controller.create
    assert_equal [:unprocessable_entity], statuses
  end

  def test_require_valid_rfc822_message_rejects_other_media_types
    controller, statuses = controller_for("x", media_type: "text/plain")
    controller.send(:require_valid_rfc822_message)
    assert_equal [:unsupported_media_type], statuses
  end

  private

  def controller_for(raw, media_type: "message/rfc822")
    controller = Controller.new
    request = Struct.new(:media_type, :body).new(media_type, raw && StringIO.new(raw))
    controller.define_singleton_method(:request) { request }
    statuses = []
    controller.define_singleton_method(:head) { |status| statuses << status }
    [controller, statuses]
  end
end
