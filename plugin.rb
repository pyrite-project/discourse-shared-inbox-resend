# frozen_string_literal: true

# name: discourse-shared-inbox-resend
# about: Shared email inboxes backed by Resend Receiving and Sending.
# version: 1.1.2
# authors: Shared Inbox contributors
# required_version: 3.5.0

enabled_site_setting :shared_inbox_enabled
register_asset "stylesheets/shared-inbox.scss"

# Discourse's admin screen filters by the directory-based plugin.id. Keep the
# metadata name and controller identity aligned with that id for every install.
metadata.name = directory_name

module ::SharedInbox
end
SharedInbox::PLUGIN_NAME = name

require_relative "lib/shared_inbox/engine"
# Discourse resolves setting validators before plugin after_initialize hooks.
require_relative "lib/shared_inbox/nickname_template_validator"

after_initialize do |plugin|
  # Preserve Discourse's directory-based ownership. Match the category used by
  # legacy settings links as well as the new plugin settings screen.
  settings_category = {
    "discourse-shared-inbox-resend" => "discourse_shared_inbox_resend",
    "shared-inbox-with-resend" => "shared_inbox_with_resend",
  }.fetch(plugin.name, "plugins")
  SiteSetting.plugins.each do |setting, owner|
    SiteSetting.categories[setting] = settings_category if owner == plugin.directory_name
  end

  register_post_custom_field_type("shared_inbox_inbound", :boolean)
  %w[configuration signature email policy resend_client inbound outbound title_sync].each do |name|
    require_relative "lib/shared_inbox/#{name}"
  end

  on(:post_created) do |post, options, _user|
    next unless SiteSetting.shared_inbox_enabled
    next if options && (options[:shared_inbox_inbound] || options[:import_mode])
    SharedInbox::Outbound.enqueue(post)
  end

  on(:topic_status_updated) do |topic, status, _enabled, **_options|
    if SiteSetting.shared_inbox_enabled && %w[closed archived autoclosed].include?(status.to_s)
      SharedInbox::TitleSync.call(topic)
    end
  end
end
