# frozen_string_literal: true

# name: shared-inbox-with-resend
# about: Shared email inboxes backed by Resend Receiving and Sending.
# version: 1.1.0
# authors: Shared Inbox contributors
# required_version: 3.5.0

enabled_site_setting :shared_inbox_enabled
register_asset "stylesheets/shared-inbox.scss"

module ::SharedInbox
  PLUGIN_NAME = "shared-inbox-with-resend"
end

require_relative "lib/shared_inbox/engine"

after_initialize do
  register_post_custom_field_type("shared_inbox_inbound", :boolean)
  %w[nickname_template nickname_template_validator configuration signature email policy resend_client inbound outbound title_sync].each do |name|
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
