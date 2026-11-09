# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe "Email username, nickname and sender templates" do
  let(:user) { User.find(1) }
  let(:inbox) { SharedInbox::Inbox.first }

  def sender
    conversation = import_mail
    conversation.inbox.update!(reply_as: "user")
    Mail::Address.new(SharedInbox::Outbound.payload(reply(conversation), conversation)["from"])
  end

  it "defaults the username and nickname to the forum identity" do
    profile = SharedInbox::Profile.for_user(user)
    expect(profile.sender_username).to eq("agent")
    expect(profile.sender_nickname).to eq("Agent Name")
    expect(profile).to be_new_record
  end

  it "uses the forum username as the nickname when no forum nickname is set" do
    user.update!(name: "")
    expect(SharedInbox::Profile.for_user(user).sender_nickname).to eq("agent")
  end

  it "normalizes the default username for email without changing the forum username" do
    user.update!(username: "Agent")
    profile = SharedInbox::Profile.create!(user: user)
    expect(profile.email_username).to eq("agent")
    expect(user.reload.username).to eq("Agent")
  end

  it "saves an email nickname independently of the email username and forum identity" do
    profile = SharedInbox::Profile.create!(user: user, email_username: "alice", email_nickname: "Mail Alice")
    profile.update!(email_nickname: "Alice Support")
    expect(profile.reload.sender_username).to eq("alice")
    expect(profile.sender_nickname).to eq("Alice Support")
    expect(user.reload.name).to eq("Agent Name")
    expect(user.username).to eq("agent")
  end

  it "uses a custom nickname and custom address in the actual outgoing From" do
    SharedInbox::Profile.create!(user: user, email_username: "alice", email_nickname: "Alice Support")
    from = sender
    expect(from.address).to eq("alice@inbox.example.com")
    expect(from.display_name).to eq("Alice Support")
  end

  it "resets an empty email nickname to the current forum nickname" do
    profile = SharedInbox::Profile.create!(user: user, email_nickname: "Mail Alias")
    profile.update!(email_nickname: "")
    user.update!(name: "New Forum Nickname")
    expect(profile.reload.sender_nickname).to eq("New Forum Nickname")
  end

  it "preserves existing saved email usernames" do
    profile = SharedInbox::Profile.create!(user: user, email_username: "user-1", signature: "Regards")
    expect(SharedInbox::Profile.for_user(user).sender_username).to eq("user-1")
    expect(profile.sender_nickname).to eq("Agent Name")
  end

  it "applies the global template to a sender display name" do
    SiteSetting.shared_inbox_nickname_template = "{user_nickname} @ XXX"
    expect(sender.display_name).to eq("Agent Name @ XXX")
  end

  it "lets an Inbox template override the global template" do
    SiteSetting.shared_inbox_nickname_template = "{user_nickname} @ Global"
    inbox.update!(nickname_template: "{user_nickname} @ Support")
    expect(sender.display_name).to eq("Agent Name @ Support")
  end

  it "inherits the global template when the Inbox template is blank" do
    SiteSetting.shared_inbox_nickname_template = "{user_nickname} @ Global"
    inbox.update!(nickname_template: "  ")
    expect(sender.display_name).to eq("Agent Name @ Global")
  end

  it "supports all documented placeholders with the user's customized values" do
    profile = SharedInbox::Profile.create!(user: user, email_username: "alice", email_nickname: "Alice")
    inbox.update!(nickname_template: "{user_nickname} ({user_username}) @ {inbox_name}/{inbox_slug}")
    expect(SharedInbox::NicknameTemplate.render(profile: profile, inbox: inbox)).to eq("Alice (alice) @ Support/support")
  end

  it "applies templates while using the Inbox sender address too" do
    SiteSetting.shared_inbox_nickname_template = "{user_nickname} @ XXX"
    conversation = import_mail
    from = Mail::Address.new(SharedInbox::Outbound.payload(reply(conversation), conversation)["from"])
    expect(from.address).to eq("support@inbox.example.com")
    expect(from.display_name).to eq("Agent Name @ XXX")
  end

  it "uses the forum nickname when both templates are empty" do
    SiteSetting.shared_inbox_nickname_template = ""
    expect(sender.display_name).to eq("Agent Name")
  end

  it "does not recursively interpret placeholders inside a user's nickname" do
    profile = SharedInbox::Profile.create!(user: user, email_nickname: "{inbox_slug}")
    inbox.update!(nickname_template: "{user_nickname} @ XXX")
    expect(SharedInbox::NicknameTemplate.render(profile: profile, inbox: inbox)).to eq("{inbox_slug} @ XXX")
  end

  it "does not treat template metacharacters as executable code" do
    inbox.update!(nickname_template: "<%= system('echo bad') %> {user_nickname}")
    expect(SharedInbox::NicknameTemplate.render(profile: SharedInbox::Profile.for_user(user), inbox: inbox)).to eq("<%= system('echo bad') %> Agent Name")
  end

  it "rejects unsupported placeholders and control characters in templates" do
    ["{unknown}", "{user_nickname", "A\nB", "x" * 256].each do |template|
      expect(inbox.update(nickname_template: template)).to eq(false)
      expect(SharedInbox::NicknameTemplateValidator.new.valid_value?(template)).to eq(false)
    end
  end

  it "allows an empty global template and validates the same syntax at both levels" do
    validator = SharedInbox::NicknameTemplateValidator.new
    expect(validator.valid_value?("")).to eq(true)
    expect(validator.valid_value?("{user_nickname} @ XXX")).to eq(true)
  end

  it "rejects nickname header injection and overlong nicknames" do
    ["Alice\r\nBcc: hidden@example.net", "x" * 121].each do |nickname|
      profile = SharedInbox::Profile.new(user: user, email_nickname: nickname)
      expect(profile).not_to be_valid
      expect(profile.errors[:email_nickname]).to be_present
    end
  end

  it "keeps quoted nicknames inside a single sender address" do
    SharedInbox::Profile.create!(user: user, email_nickname: 'Alice "Support" <alias@example.net>')
    addresses = Mail::AddressList.new(sender.to_s).addresses
    expect(addresses.length).to eq(1)
    expect(addresses.first.address).to eq("agent@inbox.example.com")
  end

  it "keeps queued identity snapshots unchanged after template and nickname changes" do
    conversation = import_mail
    post = reply(conversation)
    SharedInbox::Outbound.enqueue(post)
    original = SharedInbox::Delivery.last.payload.deep_dup
    SharedInbox::Profile.create!(user: user, email_username: "new-alias", email_nickname: "New Nickname")
    SiteSetting.shared_inbox_nickname_template = "{user_nickname} @ New Brand"
    SharedInbox::Outbound.enqueue(post)
    expect(SharedInbox::Delivery.last.payload).to eq(original)
  end
end
