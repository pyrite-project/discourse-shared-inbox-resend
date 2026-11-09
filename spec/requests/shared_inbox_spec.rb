# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Shared Inbox host integration" do
  fab!(:category)
  fab!(:admin)
  fab!(:user)
  before do
    SiteSetting.shared_inbox_enabled = true
    SiteSetting.shared_inbox_domain = "inbox.example.com"
    SiteSetting.shared_inbox_category_id = category.id
    SiteSetting.shared_inbox_resend_api_key = "test-key"
    SiteSetting.shared_inbox_nickname_template = "{user_nickname}"
    SiteSetting.shared_inbox_webhook_secret = "whsec_#{Base64.strict_encode64('test-signing-key')}"
    SiteSetting.tagging_enabled = true
    @inbox = SharedInbox::Inbox.create!(slug: "support", name: "Support")
  end

  def import_email
    event = SharedInbox::Event.create!(email_id: "test-email", svix_id: "msg_1")
    client = instance_double(SharedInbox::ResendClient, receive: {
      "from" => "customer@example.net", "to" => ["support@inbox.example.com"],
      "message_id" => "<original@example.net>", "subject" => "Need help", "text" => "A question", "headers" => {},
    })
    SharedInbox::Inbound.call(event.id, client: client)
    SharedInbox::Conversation.last
  end

  it "boots the settings page with the Discourse application layout" do
    sign_in(admin)
    get "/shared-inbox-settings"
    expect(response.status).to eq(200)
  end

  it "exposes the admin settings button while the plugin is disabled" do
    SiteSetting.shared_inbox_enabled = false
    sign_in(admin)
    get "/admin/plugins.json"
    expect(response.status).to eq(200)
    plugin = response.parsed_body.fetch("plugins").find { |entry| entry["name"] == SharedInbox::PLUGIN_NAME }
    expect(plugin).to include("has_settings" => true, "enabled" => false)
  end

  it "returns all six plugin settings through the admin plugin filter while disabled" do
    SiteSetting.shared_inbox_enabled = false
    sign_in(admin)
    get "/admin/site_settings.json", params: { plugin: SharedInbox::PLUGIN_NAME }
    expect(response.status).to eq(200)
    settings = response.parsed_body.fetch("site_settings")
    expect(settings.map { |entry| entry["setting"] }).to contain_exactly(
      "shared_inbox_enabled", "shared_inbox_domain", "shared_inbox_nickname_template",
      "shared_inbox_category_id", "shared_inbox_resend_api_key", "shared_inbox_webhook_secret",
    )
    expect(settings.map { |entry| entry["category"] }.uniq).to eq(["shared_inbox_with_resend"])
  end

  it "uses the actual post creation event and persists the inbound marker" do
    conversation = import_email
    expect(conversation.topic.first_post.reload.custom_fields["shared_inbox_inbound"]).to eq(true)
    expect(SharedInbox::Delivery.count).to eq(0)
    expect(conversation.topic.tags.pluck(:name)).to include("inbox-support")
    post = PostCreator.new(user, topic_id: conversation.topic_id, raw: "Here is the answer to your question.").create!
    expect(SharedInbox::Delivery.find_by(post_id: post.id)).to be_present
  end

  it "does not queue whispers or status action posts" do
    conversation = import_email
    PostCreator.new(admin, topic_id: conversation.topic_id, raw: "This is an internal private note.", post_type: Post.types[:whisper]).create!
    conversation.topic.update_status("closed", true, admin)
    expect(SharedInbox::Delivery.count).to eq(0)
    expect(conversation.topic.reload.title).to eq("[Closed] Need help")
    conversation.topic.update_status("closed", false, admin)
    expect(conversation.topic.reload.title).to eq("Need help")
  end

  it "retains the closed prefix while the topic remains archived" do
    topic = import_email.topic
    topic.update_status("archived", true, admin)
    topic.update_status("closed", true, admin)
    topic.update_status("closed", false, admin)
    expect(topic.reload.title).to eq("[Closed] Need help")
    topic.update_status("archived", false, admin)
    expect(topic.reload.title).to eq("Need help")
  end

  it "requires login and admin privileges for Inbox mutations" do
    get "/shared-inbox/settings.json"
    expect(response.status).to eq(403)
    sign_in(user)
    post "/shared-inbox/inboxes.json", params: { inbox: { slug: "sales", name: "Sales" } }
    expect(response.status).to eq(403)
  end

  it "does not expose API keys, signatures, delivery payloads or other users' profiles" do
    sign_in(user)
    get "/shared-inbox/settings.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body).not_to have_key("webhook_url")
    expect(response.parsed_body).not_to have_key("deliveries")
    expect(response.body).not_to include("test-key", "whsec_", "ignore_unsubscribe")
  end

  it "allows users to change only their own profile" do
    sign_in(user)
    put "/shared-inbox/profile.json", params: { profile: { user_id: admin.id, email_username: "alice", email_nickname: "Alice Support", signature: "Regards" } }
    expect(response.status).to eq(200)
    expect(SharedInbox::Profile.find_by(user_id: user.id).signature).to eq("Regards")
    expect(SharedInbox::Profile.find_by(user_id: user.id).email_nickname).to eq("Alice Support")
    expect(SharedInbox::Profile.find_by(user_id: admin.id)).to be_nil
  end

  it "defaults email identity to the forum username and nickname" do
    user.update!(name: "Forum Nickname")
    sign_in(user)
    get "/shared-inbox/settings.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["profile"]).to include(
      "email_username" => user.username.downcase,
      "email_nickname" => "Forum Nickname",
    )
  end

  it "saves an Inbox nickname template for administrators" do
    sign_in(admin)
    put "/shared-inbox/inboxes/#{@inbox.id}.json", params: { inbox: { nickname_template: "{user_nickname} @ Support" } }
    expect(response.status).to eq(200)
    expect(@inbox.reload.nickname_template).to eq("{user_nickname} @ Support")
  end

  it "denies settings access when the category is restricted" do
    group = Fabricate(:group)
    category.set_permissions(group => :full)
    category.save!
    sign_in(user)
    get "/shared-inbox/settings.json"
    expect(response.status).to eq(403)
  end

  it "accepts signed Webhooks on a login-only site without cookies" do
    SiteSetting.login_required = true
    body = { type: "email.received", data: { email_id: "webhook-email" } }.to_json
    timestamp = Time.now.to_i.to_s
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "test-signing-key", "msg_1.#{timestamp}.#{body}"))
    post "/shared-inbox/webhook", params: body, headers: {
      "CONTENT_TYPE" => "application/json", "svix-id" => "msg_1", "svix-timestamp" => timestamp,
      "svix-signature" => "v1,#{signature}",
    }
    expect(response.status).to eq(202)
    expect(SharedInbox::Event.find_by(email_id: "webhook-email")).to be_present
  end
end
