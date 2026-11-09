# frozen_string_literal: true

require "erb"
require "securerandom"

module SharedInbox
  class Outbound
    IDEMPOTENCY_WINDOW = 23.hours

    def self.enqueue(post)
      return unless Policy.reply?(post)
      conversation = Conversation.find_by(topic_id: post.topic_id)
      return unless conversation && conversation.inbox.enabled
      delivery = Delivery.create_or_find_by!(post_id: post.id) do |record|
        record.conversation_id = conversation.id
        record.payload = payload(post, conversation)
      end
      Jobs.enqueue(:shared_inbox_deliver, delivery_id: delivery.id) if delivery.state == "pending"
    end

    def self.payload(post, conversation)
      profile = Profile.for_user(post.user)
      inbox = conversation.inbox
      username = profile.sender_username
      local = inbox.reply_as == "user" ? username : inbox.slug
      from = Mail::Address.new("#{local}@#{conversation.domain}")
      from.display_name = NicknameTemplate.render(profile: profile, inbox: inbox)
      signature = profile.signature.to_s
      html = PrettyText.format_for_email(post.cooked, post)
      if signature.present?
        html += "<hr><div>#{ERB::Util.html_escape(signature).gsub("\n", '<br>')}</div>"
      end
      references = conversation.messages.order(:id).last(20).map(&:message_id)
      {
        "from" => from.to_s,
        "to" => [conversation.reply_to],
        "reply_to" => "#{inbox.slug}+#{conversation.token}@#{conversation.domain}",
        "subject" => conversation.subject.match?(/\Are:/i) ? conversation.subject : "Re: #{conversation.subject}",
        "html" => html,
        "text" => Email.html_to_text(html),
        "headers" => {
          "In-Reply-To" => conversation.last_message_id,
          "References" => references.join(" "),
          "Message-ID" => "<si-#{SecureRandom.uuid}@#{conversation.domain}>",
          "Auto-Submitted" => "no",
          "X-Shared-Inbox" => "1",
        },
      }
    end

    def self.deliver(id, client: ResendClient.new)
      Configuration.check!
      delivery = Delivery.find(id)
      # Commit the start of the provider's deduplication window BEFORE making a
      # network request. A process or DB failure after provider acceptance must
      # never reset this clock and allow a duplicate after 24 hours.
      delivery.with_lock do
        return unless eligible?(delivery)
        delivery.update!(first_attempt_at: Time.current) unless delivery.first_attempt_at
      end
      delivery.with_lock do
        return unless eligible?(delivery)
        conversation = delivery.conversation
        delivery.increment!(:attempts)
        begin
          response = client.send_email(delivery.payload, key: "si-#{conversation.token}-#{delivery.post_id}")
          raise ResendClient::Error, "resend_missing_id" if response["id"].blank?
          Message.create_or_find_by!(
            inbox_id: conversation.inbox_id,
            message_id: delivery.payload.dig("headers", "Message-ID"),
          ) do |message|
            message.conversation_id = conversation.id
            message.post_id = delivery.post_id
          end
          delivery.update!(state: "sent", resend_id: response["id"], error_code: nil)
        rescue ResendClient::Error => error
          permanent = error.code.match?(/\Aresend_http_4\d\d\z/) && error.code != "resend_http_429"
          delivery.update!(state: permanent ? "failed" : "pending", error_code: error.code)
        end
      end
    end

    def self.eligible?(delivery)
      return false unless delivery.state == "pending"
      unless Policy.reply?(delivery.post)
        delivery.update!(state: "cancelled", error_code: "no_longer_public_reply")
        return false
      end
      return false unless delivery.conversation.inbox.enabled
      if delivery.conversation.domain != Configuration.domain
        delivery.update!(state: "failed", error_code: "domain_changed")
        return false
      end
      if delivery.first_attempt_at && delivery.first_attempt_at < IDEMPOTENCY_WINDOW.ago
        delivery.update!(state: "review", error_code: "idempotency_window_expired")
        return false
      end
      true
    end
  end
end
