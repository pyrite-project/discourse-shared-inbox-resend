# frozen_string_literal: true

module Jobs
  class SharedInboxReceive < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.shared_inbox_enabled
      ::SharedInbox::Inbound.call(args[:event_id])
    end
  end
end
