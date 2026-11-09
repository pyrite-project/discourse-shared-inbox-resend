import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class SharedInboxSettings extends Component {
  @service currentUser;
  @tracked data = this.args.data;
  @tracked emailUsername = this.args.data.profile.email_username;
  @tracked emailNickname = this.args.data.profile.email_nickname;
  @tracked signature = this.args.data.profile.signature;
  @tracked editing = null;
  @tracked saved = false;
  @tracked busy = false;

  get replyAsInbox() {
    return this.editing?.reply_as === "inbox";
  }
  get replyAsUser() {
    return this.editing?.reply_as === "user";
  }

  deliveryState(state) {
    return i18n(`shared_inbox.states.${state}`);
  }

  @action changeUsername(event) {
    this.emailUsername = event.target.value;
    this.saved = false;
  }
  @action changeSignature(event) {
    this.signature = event.target.value;
    this.saved = false;
  }
  @action changeNickname(event) {
    this.emailNickname = event.target.value;
    this.saved = false;
  }
  @action newInbox() {
    this.editing = {
      slug: "",
      name: "",
      enabled: true,
      ignore_unsubscribe: true,
      reply_as: "inbox",
      nickname_template: "",
    };
  }
  @action editInbox(inbox) {
    this.editing = { ...inbox };
  }
  @action cancelEdit() {
    this.editing = null;
  }
  @action changeField(event) {
    const { name, type, checked, value } = event.target;
    this.editing = {
      ...this.editing,
      [name]: type === "checkbox" ? checked : value,
    };
  }
  async request(url, options) {
    this.busy = true;
    try {
      await ajax(url, options);
      this.data = await ajax("/shared-inbox/settings");
      return true;
    } catch (error) {
      popupAjaxError(error);
      return false;
    } finally {
      this.busy = false;
    }
  }
  @action async saveProfile(event) {
    event.preventDefault();
    this.saved = await this.request("/shared-inbox/profile", {
      type: "PUT",
      data: {
        profile: {
          email_username: this.emailUsername,
          email_nickname: this.emailNickname,
          signature: this.signature,
        },
      },
    });
    if (this.saved) {
      this.emailUsername = this.data.profile.email_username;
      this.emailNickname = this.data.profile.email_nickname;
      this.signature = this.data.profile.signature;
    }
  }
  @action async saveInbox(event) {
    event.preventDefault();
    const inbox = this.editing;
    if (
      await this.request(
        `/shared-inbox/inboxes${inbox.id ? `/${inbox.id}` : ""}`,
        {
          type: inbox.id ? "PUT" : "POST",
          data: { inbox },
        },
      )
    ) {
      this.editing = null;
    }
  }
  @action async removeInbox(inbox) {
    await this.request(`/shared-inbox/inboxes/${inbox.id}`, { type: "DELETE" });
  }
  @action async retryDelivery(delivery) {
    await this.request(`/shared-inbox/deliveries/${delivery.id}/retry`, {
      type: "POST",
    });
  }

  <template>
    <div class="shared-inbox-settings">
      <h1>{{i18n "shared_inbox.title"}}</h1>
      <p>{{i18n "shared_inbox.intro"}}</p>
      <section>
        <h2>{{i18n "shared_inbox.profile"}}</h2>
        <form {{on "submit" this.saveProfile}}>
          <label for="si-username">{{i18n
              "shared_inbox.email_username"
            }}</label>
          <div class="shared-inbox-address">
            <input
              id="si-username"
              value={{this.emailUsername}}
              maxlength="48"
              required
              {{on "input" this.changeUsername}}
            />
            <span>@{{this.data.domain}}</span>
          </div>
          <p class="description">{{i18n "shared_inbox.username_help"}}</p>
          <label for="si-nickname">{{i18n
              "shared_inbox.email_nickname"
            }}</label>
          <input
            id="si-nickname"
            value={{this.emailNickname}}
            maxlength="120"
            {{on "input" this.changeNickname}}
          />
          <p class="description">{{i18n "shared_inbox.nickname_help"}}</p>
          <label for="si-signature">{{i18n "shared_inbox.signature"}}</label>
          <textarea
            id="si-signature"
            rows="6"
            maxlength="4000"
            value={{this.signature}}
            {{on "input" this.changeSignature}}
          />
          <button
            class="btn btn-primary"
            type="submit"
            disabled={{this.busy}}
          >{{i18n "shared_inbox.save"}}</button>
          {{#if this.saved}}<span role="status">{{i18n
                "shared_inbox.saved"
              }}</span>{{/if}}
        </form>
      </section>
      {{#if this.currentUser.admin}}
        <section>
          <h2>{{i18n "shared_inbox.admin"}}</h2>
          <label for="si-webhook">{{i18n "shared_inbox.webhook"}}</label>
          <input
            id="si-webhook"
            class="shared-inbox-webhook"
            value={{this.data.webhook_url}}
            readonly
          />
          <p>{{i18n "shared_inbox.webhook_help"}}</p>
          <label for="si-global-nickname-template">{{i18n
              "shared_inbox.global_nickname_template"
            }}</label>
          <input
            id="si-global-nickname-template"
            value={{this.data.global_nickname_template}}
            readonly
          />
          <p class="description">{{i18n
              "shared_inbox.global_nickname_template_help"
            }}</p>
          <DButton
            @action={{this.newInbox}}
            @label="shared_inbox.new_inbox"
            @disabled={{this.busy}}
          />
          <ul class="shared-inbox-list">
            {{#each this.data.inboxes as |inbox|}}
              <li>
                <strong>{{inbox.name}}</strong>
                <code>{{inbox.slug}}@{{this.data.domain}}</code>
                <span>{{#if inbox.enabled}}{{i18n
                      "shared_inbox.enabled"
                    }}{{else}}{{i18n "shared_inbox.disabled"}}{{/if}}</span>
                <DButton
                  @action={{fn this.editInbox inbox}}
                  @label="shared_inbox.edit"
                  @disabled={{this.busy}}
                />
                <DButton
                  @action={{fn this.removeInbox inbox}}
                  @label="shared_inbox.delete"
                  @disabled={{this.busy}}
                />
              </li>
            {{/each}}
          </ul>
          {{#if this.editing}}
            <form class="shared-inbox-editor" {{on "submit" this.saveInbox}}>
              <label for="si-slug">{{i18n "shared_inbox.slug"}}</label>
              <input
                id="si-slug"
                name="slug"
                value={{this.editing.slug}}
                maxlength="48"
                required
                {{on "input" this.changeField}}
              />
              <label for="si-name">{{i18n "shared_inbox.name"}}</label>
              <input
                id="si-name"
                name="name"
                value={{this.editing.name}}
                maxlength="120"
                required
                {{on "input" this.changeField}}
              />
              <label><input
                  type="checkbox"
                  name="enabled"
                  checked={{this.editing.enabled}}
                  {{on "change" this.changeField}}
                />
                {{i18n "shared_inbox.enabled"}}</label>
              <label><input
                  type="checkbox"
                  name="ignore_unsubscribe"
                  checked={{this.editing.ignore_unsubscribe}}
                  {{on "change" this.changeField}}
                />
                {{i18n "shared_inbox.ignore_unsubscribe"}}</label>
              <label for="si-reply-as">{{i18n "shared_inbox.reply_as"}}</label>
              <select
                id="si-reply-as"
                name="reply_as"
                {{on "change" this.changeField}}
              >
                <option value="inbox" selected={{this.replyAsInbox}}>{{i18n
                    "shared_inbox.reply_as_inbox"
                  }}</option>
                <option value="user" selected={{this.replyAsUser}}>{{i18n
                    "shared_inbox.reply_as_user"
                  }}</option>
              </select>
              <label for="si-nickname-template">{{i18n
                  "shared_inbox.nickname_template"
                }}</label>
              <input
                id="si-nickname-template"
                name="nickname_template"
                value={{this.editing.nickname_template}}
                placeholder={{this.data.global_nickname_template}}
                maxlength="255"
                {{on "input" this.changeField}}
              />
              <p class="description">{{i18n
                  "shared_inbox.nickname_template_help"
                }}</p>
              <button
                class="btn btn-primary"
                type="submit"
                disabled={{this.busy}}
              >{{i18n "shared_inbox.save"}}</button>
              <DButton
                @action={{this.cancelEdit}}
                @label="shared_inbox.cancel"
              />
            </form>
          {{/if}}
        </section>
        <section>
          <h2>{{i18n "shared_inbox.deliveries"}}</h2>
          <p>{{i18n "shared_inbox.delivery_help"}}</p>
          <ul>
            {{#each this.data.deliveries as |delivery|}}
              <li>#{{delivery.post_id}}
                ·
                {{this.deliveryState delivery.state}}
                ·
                {{delivery.error_code}}
                ({{delivery.attempts}})
                <DButton
                  @action={{fn this.retryDelivery delivery}}
                  @label="shared_inbox.retry"
                  @disabled={{this.busy}}
                />
              </li>
            {{else}}
              <li>{{i18n "shared_inbox.no_pending"}}</li>
            {{/each}}
          </ul>
          <h3>{{i18n "shared_inbox.receive_errors"}}</h3>
          <ul>{{#each this.data.events as |event|}}<li>#{{event.id}}
                ·
                {{event.error_code}}
                ({{event.attempts}})</li>{{else}}<li>{{i18n
                  "shared_inbox.no_pending"
                }}</li>{{/each}}</ul>
        </section>
      {{/if}}
    </div>
  </template>
}
