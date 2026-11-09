# frozen_string_literal: true

SharedInbox::Engine.routes.draw do
  post "/webhook" => "webhooks#create"
  get "/settings" => "settings#show"
  put "/profile" => "settings#profile"
  post "/inboxes" => "settings#create"
  put "/inboxes/:id" => "settings#update"
  delete "/inboxes/:id" => "settings#destroy"
  post "/deliveries/:id/retry" => "settings#retry_delivery"
end

Discourse::Application.routes.append do
  mount SharedInbox::Engine, at: "/shared-inbox"
  get "/shared-inbox-settings" => "shared_inbox/settings#index"
end
