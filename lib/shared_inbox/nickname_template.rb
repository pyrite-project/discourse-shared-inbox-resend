# frozen_string_literal: true

module SharedInbox
  class NicknameTemplate
    DEFAULT = "{user_nickname}"
    PLACEHOLDERS = /\{(user_nickname|user_username|inbox_name|inbox_slug)\}/

    def self.valid?(value)
      value = value.to_s
      value.length <= 255 && !value.match?(/[[:cntrl:]]/) &&
        !value.gsub(PLACEHOLDERS, "").match?(/[{}]/)
    end

    def self.render(profile:, inbox:)
      template = inbox.nickname_template.presence || SiteSetting.shared_inbox_nickname_template.presence || DEFAULT
      values = {
        "user_nickname" => profile.sender_nickname,
        "user_username" => profile.sender_username,
        "inbox_name" => inbox.name,
        "inbox_slug" => inbox.slug,
      }
      # One pass keeps braces in a user's nickname from becoming template code.
      rendered = template.gsub(PLACEHOLDERS) { values.fetch(Regexp.last_match(1)) }
      rendered.gsub(/[[:cntrl:]]/, " ").strip.first(255).presence ||
        profile.sender_nickname.gsub(/[[:cntrl:]]/, " ").strip.first(255)
    end
  end
end
