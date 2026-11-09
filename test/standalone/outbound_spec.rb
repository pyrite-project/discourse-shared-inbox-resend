# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe SharedInbox::Outbound do
  let(:conversation) { import_mail }
  let(:post) { reply(conversation) }
  let(:client) { instance_double(SharedInbox::ResendClient, send_email: { "id" => "sent-id" }) }
  def queued
    described_class.enqueue(post)
    SharedInbox::Delivery.last
  end
  it "queues a public reply once despite duplicate events" do
    2.times { described_class.enqueue(post) }
    expect(SharedInbox::Delivery.count).to eq(1)
  end
  it "never queues a first post, whisper, system action, category change or imported mail" do
    expect(described_class.enqueue(conversation.topic.first_post)).to be_nil
    [2, 3, 4].each do |type|
      post.update!(post_type: type)
      described_class.enqueue(post)
    end
    post.update!(post_type: 1, action_code: "closed.enabled")
    described_class.enqueue(post)
    post.update!(action_code: nil, custom_fields: { "shared_inbox_inbound" => true })
    described_class.enqueue(post)
    expect(SharedInbox::Delivery.count).to eq(0)
  end
  it "does not send replies on topics that only have an Inbox tag" do
    conversation.destroy!
    described_class.enqueue(post)
    expect(SharedInbox::Delivery.count).to eq(0)
  end
  it "uses the Inbox sender, recipient, original subject and threading headers" do
    payload = queued.payload
    expect(payload["from"]).to include("support@inbox.example.com")
    expect(payload["to"]).to eq(["customer@example.net"])
    expect(payload["subject"]).to eq("Re: Help")
    expect(payload.dig("headers", "In-Reply-To")).to eq("<original@example.net>")
    expect(payload.dig("headers", "References")).to include("<original@example.net>")
    expect(payload["reply_to"]).to eq("support+#{conversation.token}@inbox.example.com")
  end
  it "uses a user alias and safely escapes a plain-text signature" do
    conversation.inbox.update!(reply_as: "user")
    SharedInbox::Profile.create!(user_id: 1, email_username: "alice", signature: "Regards\n<script>x</script>")
    payload = queued.payload
    expect(payload["from"]).to include("alice@inbox.example.com")
    expect(payload["html"]).to include("Regards<br>&lt;script&gt;x&lt;/script&gt;")
  end
  it "defaults to the forum username and nickname for an unconfigured user" do
    conversation.inbox.update!(reply_as: "user")
    from = Mail::Address.new(queued.payload["from"])
    expect(from.address).to eq("agent@inbox.example.com")
    expect(from.display_name).to eq("Agent Name")
  end
  it "records success and does not resend on a duplicate job" do
    delivery = queued
    expect(client).to receive(:send_email).once.and_return("id" => "sent-id")
    2.times { described_class.deliver(delivery.id, client: client) }
    expect(delivery.reload.state).to eq("sent")
    expect(delivery.resend_id).to eq("sent-id")
  end
  it "keeps the exact payload and idempotency key across a timeout and retry" do
    delivery = queued
    payload = delivery.payload.deep_dup
    keys = []
    allow(client).to receive(:send_email) do |body, key:|
      expect(body).to eq(payload)
      keys << key
      raise SharedInbox::ResendClient::Error, "resend_network_error" if keys.length == 1
      { "id" => "retry-id" }
    end
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("pending")
    post.update!(raw: "Edited", cooked: "<p>Edited</p>")
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("sent")
    expect(keys.uniq.length).to eq(1)
  end
  it "retains failed deliveries for admin retry" do
    delivery = queued
    allow(client).to receive(:send_email).and_raise(SharedInbox::ResendClient::Error, "resend_http_403")
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("failed")
    expect(delivery.error_code).to eq("resend_http_403")
  end
  it "automatically retries rate limiting" do
    delivery = queued
    allow(client).to receive(:send_email).and_raise(SharedInbox::ResendClient::Error, "resend_http_429")
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("pending")
  end
  it "stops retrying after the provider idempotency window" do
    delivery = queued
    delivery.update!(first_attempt_at: 24.hours.ago)
    expect(client).not_to receive(:send_email)
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("review")
  end
  it "rechecks whispers immediately before sending" do
    delivery = queued
    post.update!(post_type: Post.types[:whisper])
    expect(client).not_to receive(:send_email)
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("cancelled")
  end
  it "preserves the idempotency clock if the database fails after remote acceptance" do
    delivery = queued
    allow(SharedInbox::Message).to receive(:create_or_find_by!).and_raise("database unavailable")
    expect { described_class.deliver(delivery.id, client: client) }.to raise_error("database unavailable")
    expect(delivery.reload.state).to eq("pending")
    expect(delivery.first_attempt_at).not_to be_nil
  end
  it "rechecks moved topics immediately before sending" do
    delivery = queued
    conversation.topic.update!(category_id: Category.create!(name: "Other").id)
    expect(client).not_to receive(:send_email)
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.state).to eq("cancelled")
  end
  it "does not send from an old domain after reconfiguration" do
    delivery = queued
    SiteSetting.shared_inbox_domain = "new.example.com"
    expect(client).not_to receive(:send_email)
    described_class.deliver(delivery.id, client: client)
    expect(delivery.reload.error_code).to eq("domain_changed")
  end
  it "does not send hidden, deleted, empty, staged or unauthorized replies" do
    [{ hidden: true }, { deleted_at: Time.current }, { raw: "" }].each do |changes|
      described_class.enqueue(Post.find(post.id).tap { |p| p.assign_attributes(changes) })
    end
    User.find(1).update!(allowed: false)
    described_class.enqueue(post.reload)
    expect(SharedInbox::Delivery.count).to eq(0)
  end
end
