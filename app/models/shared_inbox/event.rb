# frozen_string_literal: true

module SharedInbox
  class Event < ActiveRecord::Base
    self.table_name = "shared_inbox_events"
  end
end
