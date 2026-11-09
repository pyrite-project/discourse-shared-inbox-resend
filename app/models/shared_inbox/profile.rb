# frozen_string_literal: true

module SharedInbox
  class Profile < ActiveRecord::Base
    self.table_name = "shared_inbox_profiles"
    belongs_to :user
    before_validation :normalize_identity
    validates :email_username, format: { with: /\A[a-z0-9][a-z0-9._-]{0,47}\z/ }, uniqueness: true
    validates :email_nickname, length: { maximum: 120 }, format: { without: /[[:cntrl:]]/ }, allow_nil: true
    validates :signature, length: { maximum: 4000 }
    validate :not_an_inbox

    def self.for_user(user)
      find_by(user_id: user.id) || new(user: user)
    end

    def sender_username
      email_username.presence || user.username.to_s.downcase
    end

    def sender_nickname
      email_nickname.presence || user.name.presence || user.username
    end

    private

    def normalize_identity
      self.email_username = email_username.to_s.strip.downcase.presence || user&.username.to_s.downcase
      self.email_nickname = email_nickname.to_s.strip.presence
    end

    def not_an_inbox
      if Inbox.exists?(slug: email_username) ||
           (email_username.to_s.match?(/\Auser-\d+\z/) && email_username != "user-#{user_id}")
        errors.add(:email_username, I18n.t("shared_inbox.errors.reserved_username"))
      end
    end
  end
end
