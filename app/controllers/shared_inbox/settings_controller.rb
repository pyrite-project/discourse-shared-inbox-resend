# frozen_string_literal: true

module SharedInbox
  class SettingsController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_logged_in
    before_action :ensure_category_access
    before_action :ensure_admin, only: %i[create update destroy retry_delivery]
    skip_before_action :check_xhr, only: :index

    def index
      render "default/empty"
    end

    def show
      profile = Profile.for_user(current_user)
      data = {
        category_id: Configuration.category.id,
        domain: SiteSetting.shared_inbox_domain,
        profile: {
          email_username: profile.sender_username,
          email_nickname: profile.sender_nickname,
          signature: profile.signature.to_s,
        },
        inboxes: Inbox.order(:slug).map { |inbox| inbox_json(inbox) },
      }
      if current_user.admin?
        data[:global_nickname_template] = SiteSetting.shared_inbox_nickname_template
        data[:webhook_url] = "#{Discourse.base_url}/shared-inbox/webhook"
        data[:deliveries] = Delivery.where.not(state: "sent").order(id: :desc).limit(50).map do |delivery|
          delivery.slice(:id, :post_id, :state, :attempts, :error_code, :created_at)
        end
        data[:events] = Event.where(processed: false).order(id: :desc).limit(20).map do |event|
          event.slice(:id, :attempts, :error_code, :created_at)
        end
      end
      render json: data
    end

    def profile
      record = Profile.find_or_initialize_by(user_id: current_user.id)
      record.assign_attributes(params.require(:profile).permit(:email_username, :email_nickname, :signature))
      save_record(record)
    end

    def create
      record = Inbox.new(inbox_params)
      save_record(record)
    end

    def update
      save_record(Inbox.find(params[:id]), inbox_params)
    end

    def destroy
      record = Inbox.find(params[:id])
      if record.destroy
        render json: success_json
      else
        render_json_error(I18n.t("shared_inbox.errors.inbox_in_use"), status: 422)
      end
    end

    def retry_delivery
      delivery = Delivery.find(params[:id])
      delivery.with_lock do
        if %w[sent cancelled review].include?(delivery.state) ||
             (delivery.first_attempt_at && delivery.first_attempt_at < Outbound::IDEMPOTENCY_WINDOW.ago)
          return render_json_error(I18n.t("shared_inbox.errors.retry_unsafe"), status: 422)
        end
        delivery.update!(state: "pending", error_code: nil)
      end
      Jobs.enqueue(:shared_inbox_deliver, delivery_id: delivery.id)
      render json: success_json
    end

    private

    def ensure_category_access
      category = Configuration.category
      raise Discourse::NotFound unless category
      guardian.ensure_can_see!(category)
      unless current_user.admin? || Category.post_create_allowed(guardian).exists?(id: category.id)
        raise Discourse::InvalidAccess
      end
    end

    def inbox_params
      params.require(:inbox).permit(:slug, :name, :enabled, :ignore_unsubscribe, :reply_as, :nickname_template)
    end

    def inbox_json(inbox)
      fields = %w[id slug name]
      fields += %w[enabled ignore_unsubscribe reply_as nickname_template] if current_user.admin?
      inbox.attributes.slice(*fields)
    end

    def save_record(record, attributes = nil)
      record.assign_attributes(attributes) if attributes
      if record.save
        render json: success_json
      else
        render_json_error(record.errors.full_messages, status: 422)
      end
    end
  end
end
