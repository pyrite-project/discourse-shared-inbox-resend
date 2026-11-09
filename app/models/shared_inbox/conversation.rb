# frozen_string_literal: true

module SharedInbox
  class Conversation < ActiveRecord::Base
    self.table_name = "shared_inbox_conversations"
    belongs_to :inbox, class_name: "SharedInbox::Inbox"
    belongs_to :topic
    has_many :messages, class_name: "SharedInbox::Message"
  end
end
