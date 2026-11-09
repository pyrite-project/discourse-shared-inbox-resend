# frozen_string_literal: true

# Run in a subprocess so the real Rails application does not share constants
# with the standalone suite's Discourse adapters.
require "rails"
require "rails/application"
require "rails/engine"
require "logger"

module SharedInbox
  PLUGIN_NAME = "discourse-shared-inbox-resend"
end
require File.join(ENV.fetch("SHARED_INBOX_PLUGIN_ROOT"), "lib/shared_inbox/engine")

class EngineBootApplication < Rails::Application
  config.root = ENV.fetch("SHARED_INBOX_BOOT_APP_ROOT")
  config.eager_load = false
  config.secret_key_base = "a" * 64
  config.logger = Logger.new(File::NULL)
end

module Discourse
  Application = ::EngineBootApplication
end

# Discourse supplies job autoloading. Record that delegation while exercising
# the real engine, application initialization and Rails reloader context.
loaded = []
Rails.autoloaders.main.define_singleton_method(:eager_load_dir) { |directory| loaded << directory }

EngineBootApplication.initialize!
EngineBootApplication.reloader.prepare!

expected = File.join(ENV.fetch("SHARED_INBOX_PLUGIN_ROOT"), "app/jobs/scheduled")
unless loaded.length >= 2 && loaded.all? { |directory| directory == expected }
  abort "Expected scheduled job path #{expected}; got #{loaded.inspect}"
end

puts "Engine boot and prepare callback passed"
