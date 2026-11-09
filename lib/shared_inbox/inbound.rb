# frozen_string_literal: true

require "securerandom"

module SharedInbox
  class Inbound
    def self.call(event_id, client: ResendClient.new)
      Configuration.check!
      event = Event.find(event_id)
      event.with_lock do
        return if event.processed
        event.increment!(:attempts)
      end
      email = Email.new(client.receive(event.email_id))
      unless email.automated?
        targets(email).each do |inbox, token|
          next if inbox.ignore_unsubscribe && email.unsubscribe?
          import(inbox, token, email, event.email_id)
        end
      end
      event.update!(processed: true, error_code: nil)
    rescue StandardError => error
      event&.update!(error_code: error.is_a?(ResendClient::Error) ? error.code : error.class.name)
      raise
    end

    def self.targets(email)
      routes = email.recipients.filter_map do |address|
        local, domain = address.split("@", 2)
        next unless domain == Configuration.domain
        slug, token = local.split("+", 2)
        inbox = Inbox.find_by(slug: slug, enabled: true)
        [inbox, token] if inbox && (token.nil? || token.match?(/\A[0-9a-f]{32}\z/))
      end
      # Prefer a thread address if a message also Ccs the plain inbox address.
      routes.group_by { |inbox, _token| inbox.id }.values.map do |entries|
        entries.find { |_inbox, token| token } || entries.first
      end
    end

    def self.import(inbox, token, email, email_id)
      # A database lock serializes concurrent deliveries to the same Inbox. The
      # post, topic, association and deduplication record commit together.
      inbox.with_lock do
        return if Message.exists?(inbox_id: inbox.id, email_id: email_id)
        return if Message.exists?(inbox_id: inbox.id, message_id: email.message_id)
        conversation = find_conversation(inbox, token, email)
        options = {
          raw: email.raw,
          skip_validations: true,
          skip_guardian: true,
          shared_inbox_inbound: true,
          custom_fields: { "shared_inbox_inbound" => true },
        }
        if conversation
          options[:topic_id] = conversation.topic_id
        else
          options[:title] = email.subject.truncate(SiteSetting.max_topic_title_length)
          options[:category] = Configuration.category.id
          options[:archetype] = Archetype.default
        end
        post = PostCreator.new(Discourse.system_user, options).create!
        unless conversation
          conversation = Conversation.create!(
            inbox_id: inbox.id,
            topic_id: post.topic_id,
            token: SecureRandom.hex(16),
            sender: email.sender,
            reply_to: email.reply_to,
            subject: email.subject,
            domain: Configuration.domain,
            last_message_id: email.message_id,
          )
        end
        conversation.update!(last_message_id: email.message_id)
        tag = Tag.find_or_create_by!(name: inbox.tag_name)
        post.topic.tags << tag unless post.topic.tags.exists?(id: tag.id)
        Message.create!(
          inbox_id: inbox.id,
          conversation_id: conversation.id,
          post_id: post.id,
          email_id: email_id,
          message_id: email.message_id,
        )
      end
    end

    def self.find_conversation(inbox, token, email)
      conversation = Conversation.find_by(inbox_id: inbox.id, token: token) if token
      unless conversation
        email.references.each do |message_id|
          message = Message.find_by(inbox_id: inbox.id, message_id: message_id)
          if message
            conversation = message.conversation
            break
          end
        end
      end
      return unless conversation && conversation.sender == email.sender
      topic = conversation.topic
      return unless topic && !topic.deleted_at && topic.category_id == Configuration.category.id
      return unless conversation.domain == Configuration.domain
      conversation
    end
  end
end
