# frozen_string_literal: true

# Exercise the real services, models, migrations and HTTP client using an in-memory
# database. Host Discourse APIs are adapters below; native host specs live in spec/.
require "active_record"
require "active_support/all"
require "rspec"
require "webmock/rspec"

ROOT = File.expand_path("../..", __dir__)
module SharedInbox; end
module SiteSetting
  class << self
    attr_accessor :shared_inbox_enabled, :shared_inbox_domain, :shared_inbox_category_id,
                  :shared_inbox_resend_api_key, :tagging_enabled, :max_post_length,
                  :max_topic_title_length, :shared_inbox_webhook_secret
  end
end
module Archetype
  def self.default; "regular"; end
end
module Jobs
  def self.enqueue(*); end
end
module Discourse
  def self.system_user; User.find(-1); end
end
module PrettyText
  def self.format_for_email(cooked, _post); cooked; end
end
class Guardian
  def initialize(user); @user = user; end
  def can_see?(_topic); @user.allowed; end
  def can_create_post?(_topic); @user.allowed; end
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
# The shipping migration uses PostgreSQL jsonb; sqlite's json type has the same
# serialization behavior needed for these tests. No changes to shipping schema.
class ActiveRecord::ConnectionAdapters::TableDefinition
  def jsonb(*args, **options); json(*args, **options); end
end
ActiveRecord::Migration.verbose = false
require File.join(ROOT, "db/migrate/20261109000001_create_shared_inbox_tables")
CreateSharedInboxTables.new.migrate(:up)
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :username; t.string :name; t.boolean :allowed, default: true; t.boolean :suspended, default: false; t.boolean :staged, default: false }
  create_table(:categories) { |t| t.string :name }
  create_table(:topics) { |t| t.integer :category_id; t.string :title; t.string :archetype, default: "regular"; t.boolean :closed, default: false; t.boolean :archived, default: false; t.datetime :deleted_at }
  create_table(:posts) { |t| t.integer :topic_id; t.integer :user_id; t.integer :post_number; t.integer :post_type, default: 1; t.text :raw; t.text :cooked; t.json :custom_fields, default: {}; t.datetime :deleted_at; t.boolean :hidden, default: false; t.string :action_code }
  create_table(:tags) { |t| t.string :name }
  create_table(:tags_topics, id: false) { |t| t.integer :tag_id; t.integer :topic_id }
end
class User < ActiveRecord::Base
  def suspended?; suspended; end
  def staged?; staged; end
end
class Category < ActiveRecord::Base; end
class Tag < ActiveRecord::Base; end
class Topic < ActiveRecord::Base
  belongs_to :category
  has_many :posts
  has_and_belongs_to_many :tags
  def first_post; posts.order(:post_number).first; end
end
class Post < ActiveRecord::Base
  belongs_to :topic
  belongs_to :user
  def self.types; { regular: 1, moderator_action: 2, small_action: 3, whisper: 4 }; end
  def revise(_user, changes, **_opts); topic.update!(changes); end
end
class PostCreator
  def initialize(user, options); @user = user; @options = options; end
  def create!
    options = @options
    topic = options[:topic_id] ? Topic.find(options[:topic_id]) : Topic.create!(title: options[:title], category_id: options[:category])
    Post.create!(topic: topic, user: @user, raw: options[:raw], cooked: "<p>Imported mail</p>", post_number: topic.posts.count + 1, custom_fields: options[:custom_fields])
  end
end
Dir[File.join(ROOT, "app/models/shared_inbox/*.rb")].sort.each { |f| require f }
%w[configuration signature email policy resend_client inbound outbound title_sync].each { |name| require File.join(ROOT, "lib/shared_inbox", name) }
I18n.load_path += Dir[File.join(ROOT, "config/locales/server.*.yml")]

module MailFixtures
  def mail(overrides = {})
    { "id" => "email-1", "from" => "Customer <customer@example.net>", "to" => ["support@inbox.example.com"], "subject" => "Help", "message_id" => "<original@example.net>", "text" => "Please help", "headers" => {} }.merge(overrides)
  end
  def event(id = "email-1")
    SharedInbox::Event.create!(email_id: id, svix_id: "msg-#{id}")
  end
  def import_mail(data = mail, id: "email-1")
    client = instance_double(SharedInbox::ResendClient, receive: data)
    SharedInbox::Inbound.call(event(id).id, client: client)
    SharedInbox::Conversation.order(:id).last
  end
  def reply(conversation)
    Post.create!(topic_id: conversation.topic_id, user: User.find(1), post_number: 2, raw: "The answer", cooked: "<p>The answer</p>")
  end
end
RSpec.configure do |config|
  config.include MailFixtures
  config.before do
    [SharedInbox::Delivery, SharedInbox::Event, SharedInbox::Message, SharedInbox::Conversation, SharedInbox::Inbox, SharedInbox::Profile, Post, Topic, Tag, Category, User].each(&:delete_all)
    ActiveRecord::Base.connection.execute("DELETE FROM tags_topics")
    SiteSetting.shared_inbox_enabled = true
    SiteSetting.shared_inbox_domain = "inbox.example.com"
    SiteSetting.shared_inbox_category_id = Category.create!(name: "Support").id
    SiteSetting.shared_inbox_resend_api_key = "test-secret"
    SiteSetting.tagging_enabled = true
    SiteSetting.max_post_length = 32_000
    SiteSetting.max_topic_title_length = 255
    User.create!(id: -1, username: "system")
    User.create!(id: 1, username: "agent", name: "Agent Name")
    SharedInbox::Inbox.create!(slug: "support", name: "Support")
  end
end
