# frozen_string_literal: true

module SharedInbox
  class Inbox < ActiveRecord::Base
    self.table_name = "shared_inbox_inboxes"
    has_many :conversations, class_name: "SharedInbox::Conversation", dependent: :restrict_with_error
    validates :slug, format: { with: /\A[a-z0-9][a-z0-9-]{0,47}\z/ }, uniqueness: true
    validates :name, presence: true, length: { maximum: 120 }
    validates :reply_as, inclusion: { in: %w[inbox user] }
    validate :immutable_slug
    validate :not_a_user_alias

    def tag_name
      "inbox-#{slug}"
    end

    private

    def immutable_slug
      if persisted? && will_save_change_to_slug? && conversations.exists?
        errors.add(:slug, I18n.t("shared_inbox.errors.slug_in_use"))
      end
    end

    def not_a_user_alias
      if slug.to_s.match?(/\Auser-\d+\z/) || Profile.exists?(email_username: slug)
        errors.add(:slug, I18n.t("shared_inbox.errors.reserved_username"))
      end
    end
  end
end
