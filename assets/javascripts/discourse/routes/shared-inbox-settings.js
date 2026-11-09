import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { service } from "@ember/service";

export default class SharedInboxSettingsRoute extends DiscourseRoute {
  @service router;

  beforeModel() {
    if (!this.currentUser) {
      return this.router.replaceWith("login");
    }
  }

  model() {
    return ajax("/shared-inbox/settings");
  }
}
