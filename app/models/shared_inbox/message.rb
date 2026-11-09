# frozen_string_literal: true

module SharedInbox
  class Message < ActiveRecord::Base
    self.table_name = "shared_inbox_messages"
    belongs_to :conversation, class_name: "SharedInbox::Conversation"
  end
end
