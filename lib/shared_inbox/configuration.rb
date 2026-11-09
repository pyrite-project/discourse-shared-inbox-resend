# frozen_string_literal: true

module SharedInbox
  class Configuration
    class Invalid < StandardError; end

    def self.domain
      value = SiteSetting.shared_inbox_domain.to_s.strip.downcase
      unless value.length <= 253 && value.match?(/\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}\z/)
        raise Invalid, "invalid_domain"
      end
      value
    end

    def self.category
      Category.find_by(id: SiteSetting.shared_inbox_category_id.to_i)
    end

    def self.check!
      raise Invalid, "disabled" unless SiteSetting.shared_inbox_enabled
      domain
      raise Invalid, "missing_category" unless category
      raise Invalid, "tagging_disabled" unless SiteSetting.tagging_enabled
      raise Invalid, "missing_api_key" if SiteSetting.shared_inbox_resend_api_key.blank?
    end
  end
end
