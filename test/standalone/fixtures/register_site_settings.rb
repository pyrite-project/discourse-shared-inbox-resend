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
  Metadata = Struct.new(:name)
  attr_reader :directory_name, :metadata, :initializers

  def initialize(path, directory_name)
    @directory_name = directory_name
    @metadata = Metadata.new(File.read(path).match(/^# name:\s*(.+)$/)[1].strip)
    @initializers = []
    instance_eval(File.read(path), path)
  end

  def name
    metadata.name
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
owners_before = SiteSetting.plugins.dup
plugin.initializers.each { |initializer| initializer.call(plugin) }

expected = %i[
  shared_inbox_enabled shared_inbox_domain shared_inbox_nickname_template
  shared_inbox_category_id shared_inbox_resend_api_key shared_inbox_webhook_secret
].sort
# The new plugin settings screen sends serialized plugin.id (the directory),
# while legacy screens filter by plugin.name. Both must resolve the same rows.
[plugin.directory_name, plugin.name].uniq.each do |filter|
  owned = SiteSetting.plugins.select { |_name, owner| owner == filter }.keys.sort
  abort "Settings invisible to plugin filter #{filter}: #{owned.inspect}" unless owned == expected
end
abort "Plugin id and name differ" unless plugin.name == plugin.directory_name
abort "Controller plugin id differs" unless SharedInbox::PLUGIN_NAME == plugin.directory_name
abort "Discourse's setting ownership was rewritten" unless SiteSetting.plugins == owners_before
abort "Other plugin ownership changed" unless SiteSetting.plugins[:another_plugin_setting] == "another-plugin"
abort "Plugin was enabled during registration" unless SiteSetting.shared_inbox_enabled == false
after = [SiteSetting.values, SiteSetting.secret_settings, SiteSetting.client_settings]
abort "Stored values or visibility metadata changed" unless before == after
abort "Secret exposed to client" unless (SiteSetting.secret_settings & SiteSetting.client_settings).empty?

%w[en zh_CN].each do |locale|
  translations = YAML.load_file(File.join(root, "config/locales/client.#{locale}.yml"))
  # Match AdminPlugin.settingCategoryName: use the translated snake-case name,
  # falling back to the standard plugins category for a custom checkout name.
  category_name = plugin.name.tr("-", "_")
  label = translations.dig(locale, "admin_js", "admin", "site_settings", "categories", category_name)
  category = label.present? ? category_name : "plugins"
  abort "Admin category does not match settings" unless expected.all? { |name| SiteSetting.categories[name] == category }
end

puts "Plugin settings registration passed: #{plugin.directory_name}"
