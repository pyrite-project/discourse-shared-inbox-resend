# frozen_string_literal: true

class AddSharedInboxNicknames < ActiveRecord::Migration[7.0]
  def change
    add_column :shared_inbox_profiles, :email_nickname, :string, limit: 120
    add_column :shared_inbox_inboxes, :nickname_template, :string, limit: 255, null: false, default: ""
  end
end
