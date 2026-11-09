# frozen_string_literal: true

module SharedInbox
  class Delivery < ActiveRecord::Base
    self.table_name = "shared_inbox_deliveries"
    belongs_to :conversation, class_name: "SharedInbox::Conversation"
    belongs_to :post
  end
end
