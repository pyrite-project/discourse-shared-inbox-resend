# frozen_string_literal: true
require_relative "spec_helper"

RSpec.describe SharedInbox::Inbound do
  it "imports the email and identifies the Inbox with a tag" do
    conversation = import_mail
    expect(conversation.sender).to eq("customer@example.net")
    expect(conversation.topic.tags.pluck(:name)).to eq(["inbox-support"])
    expect(conversation.topic.first_post.custom_fields["shared_inbox_inbound"]).to eq(true)
    expect(SharedInbox::Event.last.processed).to eq(true)
  end
  it "deduplicates webhook retries" do
    imported = import_mail
    client = instance_double(SharedInbox::ResendClient)
    expect(client).not_to receive(:receive)
    described_class.call(SharedInbox::Event.last.id, client: client)
    expect(imported.topic.posts.count).to eq(1)
  end
  it "deduplicates a repeated Message-ID with a different provider ID" do
    import_mail
    import_mail(mail, id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(1)
    expect(Post.count).to eq(1)
  end
  it "threads replies by In-Reply-To and sender" do
    conversation = import_mail
    import_mail(mail("message_id" => "<next@example.net>", "headers" => { "in-reply-to" => conversation.last_message_id }), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(1)
    expect(conversation.topic.posts.count).to eq(2)
    expect(conversation.reload.last_message_id).to eq("<next@example.net>")
  end
  it "threads replies by References with case-insensitive headers" do
    conversation = import_mail
    import_mail(mail("message_id" => "<next@example.net>", "headers" => { "References" => "<unknown@x.net> #{conversation.last_message_id}" }), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(1)
  end
  it "uses a token address if a provider rewrites Message-ID" do
    conversation = import_mail
    import_mail(mail("message_id" => "<next@example.net>", "to" => ["support+#{conversation.token}@inbox.example.com"]), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(1)
  end
  it "does not attach an unrelated sender to a private conversation" do
    conversation = import_mail
    import_mail(mail("from" => "stranger@example.net", "message_id" => "<stranger@example.net>", "headers" => { "In-Reply-To" => conversation.last_message_id }), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(2)
    expect(conversation.topic.posts.count).to eq(1)
  end
  it "does not merge equal subjects without references" do
    import_mail
    import_mail(mail("message_id" => "<different@example.net>"), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(2)
  end
  it "isolates threads by Inbox" do
    SharedInbox::Inbox.create!(slug: "sales", name: "Sales")
    conversation = import_mail
    import_mail(mail("to" => ["sales@inbox.example.com"], "message_id" => "<next@example.net>", "headers" => { "in-reply-to" => conversation.last_message_id }), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(2)
  end
  it "imports a message addressed to two Inboxes once per Inbox" do
    SharedInbox::Inbox.create!(slug: "sales", name: "Sales")
    import_mail(mail("to" => ["support@inbox.example.com", "sales@inbox.example.com"]))
    expect(SharedInbox::Conversation.count).to eq(2)
  end
  it "ignores List-Unsubscribe by default" do
    import_mail(mail("headers" => { "List-Unsubscribe" => "<mailto:unsub@example.net>" }))
    expect(Post.count).to eq(0)
  end
  it "can accept Unsubscribe emails per Inbox" do
    SharedInbox::Inbox.first.update!(ignore_unsubscribe: false)
    import_mail(mail("headers" => { "Unsubscribe" => "yes" }))
    expect(Post.count).to eq(1)
  end
  it "ignores its own outgoing mail and auto responders" do
    import_mail(mail("headers" => { "Auto-Submitted" => "auto-replied" }))
    import_mail(mail("headers" => { "X-Shared-Inbox" => "1" }), id: "email-2")
    expect(Post.count).to eq(0)
  end
  it "ignores disabled Inboxes and wrong domains" do
    SharedInbox::Inbox.first.update!(enabled: false)
    import_mail
    import_mail(mail("to" => ["support@other.example.com"]), id: "email-2")
    expect(Post.count).to eq(0)
  end
  it "accepts ordinary messages sent from the configured domain" do
    import_mail(mail("from" => "colleague@inbox.example.com"))
    expect(Post.count).to eq(1)
  end
  it "does not thread into a moved topic" do
    conversation = import_mail
    conversation.topic.update!(category_id: Category.create!(name: "Elsewhere").id)
    import_mail(mail("message_id" => "<next@example.net>", "headers" => { "In-Reply-To" => conversation.last_message_id }), id: "email-2")
    expect(SharedInbox::Conversation.count).to eq(2)
  end
  it "rolls back the entire import if tag assignment fails" do
    allow(Tag).to receive(:find_or_create_by!).and_raise("database failure")
    expect { import_mail }.to raise_error("database failure")
    expect(Post.count).to eq(0)
    expect(SharedInbox::Conversation.count).to eq(0)
    expect(SharedInbox::Event.last.processed).to eq(false)
  end
end
