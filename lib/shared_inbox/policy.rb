# frozen_string_literal: true

module SharedInbox
  class Policy
    def self.reply?(post)
      return false unless post && post.post_number.to_i > 1
      return false unless post.post_type == Post.types[:regular]
      return false if post.deleted_at || post.hidden || post.raw.blank? || post.user_id.to_i <= 0
      return false if post.custom_fields["shared_inbox_inbound"] || post.action_code.present?
      topic = post.topic
      return false unless topic && !topic.deleted_at && topic.archetype == Archetype.default
      return false unless topic.category_id == SiteSetting.shared_inbox_category_id.to_i
      user = post.user
      return false unless user && !user.suspended? && !user.staged?
      Guardian.new(user).can_see?(topic) && Guardian.new(user).can_create_post?(topic)
    end
  end
end
