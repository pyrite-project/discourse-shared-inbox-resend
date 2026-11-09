# frozen_string_literal: true

module SharedInbox
  # Deliberately use a stateless controller: webhooks must work on login-only
  # forums without Discourse's XHR/session/CSRF/login middleware. Svix is auth.
  class WebhooksController < ::ActionController::Metal
    include ::ActionController::Head
    MAX_BODY_BYTES = 256 * 1024

    def create
      return head :not_found unless SiteSetting.shared_inbox_enabled
      return head 413 if request.content_length.to_i > MAX_BODY_BYTES
      body = request.body.read(MAX_BODY_BYTES + 1)
      return head 413 if body.bytesize > MAX_BODY_BYTES
      Signature.verify!(
        body: body,
        id: request.headers["svix-id"],
        timestamp: request.headers["svix-timestamp"],
        signatures: request.headers["svix-signature"],
        secret: SiteSetting.shared_inbox_webhook_secret,
      )
      payload = JSON.parse(body)
      return head :ok unless payload.is_a?(Hash) && payload["type"] == "email.received"
      email_id = payload.dig("data", "email_id")
      return head :unprocessable_entity unless email_id.is_a?(String) && email_id.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
      event = Event.create_or_find_by!(email_id: email_id) do |record|
        record.svix_id = request.headers["svix-id"].to_s.first(255)
      end
      Jobs.enqueue(:shared_inbox_receive, event_id: event.id) unless event.processed
      head :accepted
    rescue Signature::Invalid
      head :unauthorized
    rescue JSON::ParserError, TypeError
      head :bad_request
    end
  end
end
