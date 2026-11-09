# frozen_string_literal: true

module SharedInbox
  class Profile < ActiveRecord::Base
    self.table_name = "shared_inbox_profiles"
    belongs_to :user
    before_validation { self.email_username = email_username.to_s.strip.downcase }
    validates :email_username, format: { with: /\A[a-z0-9][a-z0-9._-]{0,47}\z/ }, uniqueness: true
    validates :signature, length: { maximum: 4000 }
    validate :not_an_inbox

    private

    def not_an_inbox
      if Inbox.exists?(slug: email_username) ||
           (email_username.to_s.match?(/\Auser-\d+\z/) && email_username != "user-#{user_id}")
        errors.add(:email_username, I18n.t("shared_inbox.errors.reserved_username"))
      end
    end
  end
end
