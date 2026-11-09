# frozen_string_literal: true

# Exercise plugin.rb in Discourse's ordering: activate plugin code, load setting
# definitions using the installation directory as owner, then run initializers.
# These small host adapters do not replace the native admin request specs.
require "active_support/all"
require "rails"
require "rails/engine"
require "yaml"

class SiteSetting
  class << self
    attr_accessor :plugins, :values, :categories, :secret_settings, :client_settings
  end
end

class PluginActivationAdapter
  attr_reader :directory_name, :name, :initializers

  def initialize(path, directory_name)
    @directory_name = directory_name
    @name = File.read(path).match(/^# name:\s*(.+)$/)[1].strip
    @initializers = []
    instance_eval(File.read(path), path)
  end

  def enabled_site_setting(_name); end
  def register_asset(*); end
  def register_post_custom_field_type(*); end
  def on(*); end
  def after_initialize(&block)
    @initializers << block
  end
end

root = ENV.fetch("SHARED_INBOX_PLUGIN_ROOT")
plugin = PluginActivationAdapter.new(File.join(root, "plugin.rb"), ARGV.fetch(0))
SiteSetting.plugins = { another_plugin_setting: "another-plugin" }
SiteSetting.values = { shared_inbox_domain: "configured.example.com" }
SiteSetting.categories = {}
SiteSetting.secret_settings = []
SiteSetting.client_settings = []

YAML.load_file(File.join(root, "config/settings.yml")).each do |category, definitions|
  definitions.each do |name, options|
    key = name.to_sym
    # Discourse resolves custom validators while loading settings, before
    # plugin after_initialize callbacks or Zeitwerk setup can load them.
    options.fetch("validator").constantize if options["validator"]
    SiteSetting.plugins[key] = plugin.directory_name
    SiteSetting.values[key] = options.fetch("default") unless SiteSetting.values.key?(key)
    SiteSetting.categories[key] = category
    SiteSetting.secret_settings << key if options["secret"]
    SiteSetting.client_settings << key if options["client"]
    SiteSetting.define_singleton_method(key) { SiteSetting.values.fetch(key) }
  end
end

before = [SiteSetting.values.dup, SiteSetting.secret_settings.dup, SiteSetting.client_settings.dup]
plugin.initializers.each { |initializer| initializer.call(plugin) }

expected = %i[
  shared_inbox_enabled shared_inbox_domain shared_inbox_nickname_template
  shared_inbox_category_id shared_inbox_resend_api_key shared_inbox_webhook_secret
].sort
owned = SiteSetting.plugins.select { |_name, owner| owner == plugin.name }.keys.sort
abort "Settings invisible to plugin filter: #{owned.inspect}" unless owned == expected
abort "Other plugin ownership changed" unless SiteSetting.plugins[:another_plugin_setting] == "another-plugin"
abort "Plugin was enabled during registration" unless SiteSetting.shared_inbox_enabled == false
after = [SiteSetting.values, SiteSetting.secret_settings, SiteSetting.client_settings]
abort "Stored values or visibility metadata changed" unless before == after
abort "Secret exposed to client" unless (SiteSetting.secret_settings & SiteSetting.client_settings).empty?

category = "shared_inbox_with_resend"
abort "Missing settings group" unless expected.all? { |name| SiteSetting.categories[name] == category }
%w[en zh_CN].each do |locale|
  translations = YAML.load_file(File.join(root, "config/locales/client.#{locale}.yml"))
  label = translations.dig(locale, "admin_js", "admin", "site_settings", "categories", category)
  abort "Missing #{locale} admin category label" if label.blank?
end

puts "Plugin settings registration passed: #{plugin.directory_name}"
