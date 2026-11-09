# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe "Email parsing, configuration and Inbox models" do
  it "treats header names without case sensitivity" do
    expect(SharedInbox::Email.new(mail("headers" => { "LIST-UNSUBSCRIBE" => "yes" })).unsubscribe?).to eq(true)
  end
  it "rejects injected addresses and malformed Message-IDs" do
    expect(SharedInbox::Email.address("a@example.net\r\nBcc: secret@example.net")).to be_nil
    expect { SharedInbox::Email.new(mail("message_id" => "bad\r\nheader")) }.to raise_error(SharedInbox::Email::Invalid)
  end
  it "keeps untrusted Markdown and mentions inside a sufficiently long fence" do
    raw = SharedInbox::Email.new(mail("text" => "```\n@all ![track](https://bad.example/x)\n```")).raw
    expect(raw).to include("````text")
    expect(raw).to end_with("````")
  end
  it "uses readable HTML text without executing scripts or external resources" do
    text = SharedInbox::Email.new(mail("text" => nil, "html" => "<script>secret()</script><p>Hello<br>World</p><img src='https://bad.example/x'>")).text
    expect(text).to include("Hello\nWorld")
    expect(text).not_to include("secret()", "https://bad.example")
  end
  it "uses the explicit Reply-To address" do
    expect(SharedInbox::Email.new(mail("reply_to" => ["Contact <contact@example.net>"])).reply_to).to eq("contact@example.net")
  end
  it "defaults malformed Reply-To to the sender" do
    expect(SharedInbox::Email.new(mail("reply_to" => ["broken"])).reply_to).to eq("customer@example.net")
  end
  it "refuses missing or invalid configuration" do
    ["", "https://example.com", "foo@example.com", "example.com\r\n"].each do |domain|
      # Whitespace is deliberately trimmed, so the final entry is valid after normalization.
      next if domain == "example.com\r\n"
      SiteSetting.shared_inbox_domain = domain
      expect { SharedInbox::Configuration.check! }.to raise_error(SharedInbox::Configuration::Invalid)
    end
  end
  it "requires tagging" do
    SiteSetting.tagging_enabled = false
    expect { SharedInbox::Configuration.check! }.to raise_error(SharedInbox::Configuration::Invalid, "tagging_disabled")
  end
  it "keeps hostile long fence sequences within the post length budget" do
    raw = SharedInbox::Email.new(mail("text" => "`" * 40_000)).raw
    expect(raw.length).to be <= SiteSetting.max_post_length
  end
  it "keeps Inbox slugs immutable once in use" do
    inbox = import_mail.inbox
    expect(inbox.update(slug: "renamed")).to eq(false)
  end
  it "does not delete Inboxes with conversations" do
    expect(import_mail.inbox.destroy).to eq(false)
  end
  it "validates sender modes and local-part syntax" do
    expect(SharedInbox::Inbox.new(slug: "x@y", name: "Bad", reply_as: "unknown")).not_to be_valid
    expect(SharedInbox::Profile.new(user_id: 1, email_username: "x+y")).not_to be_valid
  end
  it "prevents duplicate and reserved user aliases" do
    expect(SharedInbox::Profile.new(user_id: 1, email_username: "support")).not_to be_valid
    expect(SharedInbox::Profile.new(user_id: 1, email_username: "user-2")).not_to be_valid
    SharedInbox::Profile.create!(user_id: 1, email_username: "alice")
    expect(SharedInbox::Profile.new(user_id: 2, email_username: "alice")).not_to be_valid
    expect(SharedInbox::Inbox.new(slug: "alice", name: "Alice")).not_to be_valid
  end
  it "normalizes aliases and limits signatures" do
    profile = SharedInbox::Profile.new(user_id: 1, email_username: " Alice ", signature: "x" * 4001)
    expect(profile).not_to be_valid
    expect(profile.email_username).to eq("alice")
  end
end

RSpec.describe SharedInbox::TitleSync do
  it "prefixes when either closed or archived and removes only when both clear" do
    conversation = import_mail
    topic = conversation.topic
    topic.update!(closed: true)
    described_class.call(topic)
    expect(topic.reload.title).to eq("[Closed] Help")
    topic.update!(archived: true, closed: false)
    described_class.call(topic)
    expect(topic.reload.title).to eq("[Closed] Help")
    topic.update!(archived: false)
    described_class.call(topic)
    expect(topic.reload.title).to eq("Help")
    expect(conversation.reload.subject).to eq("Help")
  end
  it "does not duplicate the prefix or change unrelated topics" do
    topic = import_mail.topic
    topic.update!(closed: true)
    2.times { described_class.call(topic.reload) }
    expect(topic.reload.title).to eq("[Closed] Help")
    other = Topic.create!(category_id: topic.category_id, title: "Other", closed: true)
    described_class.call(other)
    expect(other.reload.title).to eq("Other")
  end
end
