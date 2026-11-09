# frozen_string_literal: true

module SharedInbox
  class TitleSync
    def self.call(topic)
      return unless topic.category_id == SiteSetting.shared_inbox_category_id.to_i
      return unless Conversation.exists?(topic_id: topic.id)
      plain = topic.title.sub(/\A(?:\[Closed\]\s*)+/, "")
      title = topic.closed || topic.archived ? "[Closed] #{plain}" : plain
      return if title == topic.title
      # Title-only revisions do not create an outbound post. Keep the original
      # email subject in Conversation, so [Closed] never leaks into email threads.
      topic.first_post.revise(
        Discourse.system_user,
        { title: title },
        skip_validations: true,
        bypass_bump: true,
      )
    end
  end
end
