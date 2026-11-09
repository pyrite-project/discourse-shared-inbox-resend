# frozen_string_literal: true

module Jobs
  class SharedInboxDeliver < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.shared_inbox_enabled
      ::SharedInbox::Outbound.deliver(args[:delivery_id])
    end
  end
end
