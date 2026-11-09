# frozen_string_literal: true

require_relative "nickname_template"

module SharedInbox
  class NicknameTemplateValidator
    def initialize(*); end

    def valid_value?(value)
      NicknameTemplate.valid?(value)
    end

    def error_message
      I18n.t("shared_inbox.errors.invalid_nickname_template")
    end
  end
end
