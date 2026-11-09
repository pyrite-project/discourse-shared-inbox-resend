# frozen_string_literal: true

module Jobs
  class SharedInboxRecover < ::Jobs::Scheduled
    every 5.minutes

    def execute(_args)
      return unless SiteSetting.shared_inbox_enabled
      # Requeue records that survived a process/Redis failure after DB commit.
      ::SharedInbox::Event.where(processed: false).where("updated_at < ?", 5.minutes.ago).order(:updated_at).limit(100).each do |event|
        event.touch
        Jobs.enqueue(:shared_inbox_receive, event_id: event.id)
      end
      ::SharedInbox::Delivery.where(state: "pending").where("updated_at < ?", 5.minutes.ago).order(:updated_at).limit(100).each do |delivery|
        delivery.touch
        Jobs.enqueue(:shared_inbox_deliver, delivery_id: delivery.id)
      end
    end
  end
end
