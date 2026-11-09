# frozen_string_literal: true

class CreateSharedInboxTables < ActiveRecord::Migration[7.0]
  def change
    create_table :shared_inbox_inboxes do |t|
      t.string :slug, null: false, limit: 48
      t.string :name, null: false, limit: 120
      t.boolean :enabled, null: false, default: true
      t.boolean :ignore_unsubscribe, null: false, default: true
      t.string :reply_as, null: false, default: "inbox"
      t.timestamps
    end
    add_index :shared_inbox_inboxes, :slug, unique: true

    create_table :shared_inbox_conversations do |t|
      t.bigint :inbox_id, null: false
      t.bigint :topic_id, null: false
      t.string :token, null: false
      t.string :sender, null: false
      t.string :reply_to, null: false
      t.string :subject, null: false
      t.string :domain, null: false
      t.string :last_message_id, null: false
      t.timestamps
    end
    add_index :shared_inbox_conversations, :topic_id, unique: true
    add_index :shared_inbox_conversations, :token, unique: true
    add_index :shared_inbox_conversations, :inbox_id

    create_table :shared_inbox_messages do |t|
      t.bigint :inbox_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :post_id, null: false
      t.string :email_id
      t.string :message_id, null: false
      t.timestamps
    end
    add_index :shared_inbox_messages, %i[inbox_id email_id], unique: true
    add_index :shared_inbox_messages, %i[inbox_id message_id], unique: true
    add_index :shared_inbox_messages, :conversation_id

    create_table :shared_inbox_events do |t|
      t.string :email_id, null: false
      t.string :svix_id, null: false
      t.boolean :processed, null: false, default: false
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.timestamps
    end
    add_index :shared_inbox_events, :email_id, unique: true

    create_table :shared_inbox_deliveries do |t|
      t.bigint :post_id, null: false
      t.bigint :conversation_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.string :resend_id
      t.string :error_code
      t.integer :attempts, null: false, default: 0
      t.datetime :first_attempt_at
      t.timestamps
    end
    add_index :shared_inbox_deliveries, :post_id, unique: true
    add_index :shared_inbox_deliveries, %i[state created_at]

    create_table :shared_inbox_profiles do |t|
      t.bigint :user_id, null: false
      t.string :email_username, null: false
      t.text :signature, null: false, default: ""
      t.timestamps
    end
    add_index :shared_inbox_profiles, :user_id, unique: true
    add_index :shared_inbox_profiles, :email_username, unique: true
  end
end
