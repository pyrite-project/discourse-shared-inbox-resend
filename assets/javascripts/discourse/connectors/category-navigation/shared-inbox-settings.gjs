import Component from "@glimmer/component";
import { service } from "@ember/service";
import { LinkTo } from "@ember/routing";
import { i18n } from "discourse-i18n";

export default class SharedInboxCategoryLink extends Component {
  @service currentUser;
  @service siteSettings;

  get visible() {
    return (
      this.currentUser &&
      this.siteSettings.shared_inbox_enabled &&
      Number(this.args.outletArgs.category.id) ===
        Number(this.siteSettings.shared_inbox_category_id)
    );
  }

  <template>
    {{#if this.visible}}
      <LinkTo
        @route="shared-inbox-settings"
        class="btn btn-default shared-inbox-settings-link"
      >
        {{i18n "shared_inbox.title"}}
      </LinkTo>
    {{/if}}
  </template>
}
