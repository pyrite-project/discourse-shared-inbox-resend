# frozen_string_literal: true
require_relative "spec_helper"
require "action_controller"
require "rack/mock"
require File.join(ROOT, "app/controllers/shared_inbox/webhooks_controller")

RSpec.describe SharedInbox::WebhooksController do
  let(:secret_key) { "webhook-signing-key" }
  let(:body) { { type: "email.received", data: { email_id: "email-1" } }.to_json }
  before { SiteSetting.shared_inbox_webhook_secret = "whsec_#{Base64.strict_encode64(secret_key)}" }
  def request(body: self.body, signature: nil, timestamp: Time.now.to_i.to_s)
    id = "msg_123"
    signed = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret_key, "#{id}.#{timestamp}.#{body}"))
    env = Rack::MockRequest.env_for("/shared-inbox/webhook", method: "POST", input: body,
      "CONTENT_TYPE" => "application/json", "HTTP_SVIX_ID" => id,
      "HTTP_SVIX_TIMESTAMP" => timestamp, "HTTP_SVIX_SIGNATURE" => signature || "v1,#{signed}")
    described_class.action(:create).call(env).first
  end
  it "accepts signed webhooks without a session, CSRF token or XHR header" do
    expect(Jobs).to receive(:enqueue).with(:shared_inbox_receive, event_id: kind_of(Integer))
    expect(request).to eq(202)
    expect(SharedInbox::Event.count).to eq(1)
  end
  it "deduplicates duplicate events in the database" do
    2.times { expect(request).to eq(202) }
    expect(SharedInbox::Event.count).to eq(1)
  end
  it "rejects unsigned or invalid signatures" do
    expect(request(signature: "v1,invalid")).to eq(401)
    expect(SharedInbox::Event.count).to eq(0)
  end
  it "acknowledges unrelated signed event types" do
    expect(request(body: { type: "email.delivered" }.to_json)).to eq(200)
    expect(SharedInbox::Event.count).to eq(0)
  end
  it "rejects malformed data, invalid JSON and paths in email ids" do
    expect(request(body: "{")).to eq(400)
    expect(request(body: { type: "email.received", data: { email_id: "../other" } }.to_json)).to eq(422)
  end
  it "rejects stale signatures" do
    expect(request(timestamp: 10.minutes.ago.to_i.to_s)).to eq(401)
  end
  it "rejects oversized bodies before verification" do
    expect(request(body: "x" * (256 * 1024 + 1))).to eq(413)
  end
  it "does not process webhooks while disabled" do
    SiteSetting.shared_inbox_enabled = false
    expect(request).to eq(404)
  end
end
