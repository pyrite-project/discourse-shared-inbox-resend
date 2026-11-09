# Shared Inbox with Resend

[中文说明](README.zh_CN.md)

A Discourse plugin that turns a category into a shared email inbox using Resend Receiving and Sending. Requires Discourse 3.5+ with tagging, PostgreSQL, Redis/Sidekiq and a domain configured for both receiving and sending in Resend. The plugin has English and Simplified Chinese translations.

## Install

For a standard Docker Discourse install, add this clone command to the existing `after_code` plugin clone commands in `/var/discourse/containers/app.yml`:

```yaml
- git clone https://github.com/pyrite-project/discourse-shared-inbox-resend.git
```

Rebuild from `/var/discourse`:

```sh
./launcher rebuild app
```

For an existing Discourse development checkout, run these commands in the Discourse root:

```sh
git clone https://github.com/pyrite-project/discourse-shared-inbox-resend.git plugins/discourse-shared-inbox-resend
bundle exec rake db:migrate
```

Rebuild frontend assets and restart the web and Sidekiq processes using your installation's standard procedure. Updating to 1.1.0 adds a database migration for email nicknames and Inbox templates; run migrations before restarting, or rebuild the Docker installation.

## Configure

1. Configure a dedicated domain/subdomain in Resend, including its receiving MX records and sending SPF/DKIM records. Both receiving and sending must be enabled. Avoid replacing existing organizational mail MX records unintentionally.
2. Create a Discourse category and grant the intended team permission to see and reply. All imported content uses this category's permissions. Enable Discourse tagging.
3. In **Admin → Site settings**, open **Shared Inbox with Resend** (or search `shared_inbox`) and configure:
   - `shared_inbox_domain`: for example `inbox.example.com`, without an address, scheme or path.
   - `shared_inbox_category_id`: the receiving category.
   - `shared_inbox_nickname_template`: global sender display name, for example `{user_nickname} @ XXX`.
   - `shared_inbox_resend_api_key`: a Resend key with access to retrieve received emails and send messages.
   - `shared_inbox_webhook_secret`: the signing secret for the Webhook below (`whsec_...`). This is not your API key.
   - `shared_inbox_enabled`: enable after configuration.
4. In Resend create an HTTPS Webhook at `https://YOUR-FORUM/shared-inbox/webhook`, subscribe to **`email.received`**, and copy its signing secret into the setting above. Include the forum's base path if installed under a subfolder. Keep the original body and `svix-id`, `svix-timestamp`, `svix-signature` headers intact at your reverse proxy.
5. Open the receiving category and select **Shared Inbox with Resend**. As an administrator create Inboxes: `support` receives `support@inbox.example.com`, `sales` receives `sales@inbox.example.com`. The same page is available at `/shared-inbox-settings`.
6. Send a message from an external mailbox. Check that a topic with the `inbox-support` tag appears. Reply in Discourse and confirm that the email stays in the original external thread. Test a whisper and close/reopen the topic before rollout.

All six site settings are available while the plugin is disabled. Administrators can also open `/admin/site_settings/category/discourse_shared_inbox_resend` directly. The default checkout directory is `discourse-shared-inbox-resend`. Existing `shared-inbox-with-resend` checkouts remain supported without renaming; those installations retain the `shared_inbox_with_resend` settings category. The plugin settings page uses the installation directory as its identity, matching Discourse’s settings API. After updating the plugin, restart/rebuild Discourse and refresh the admin page.

The API key and Webhook signing secret are server-only settings. No Resend credentials are entered in the user settings page.

## Inboxes and personal identity

Each Inbox has an enabled switch, **Ignore Unsubscribe headers**, a sender mode and an optional sender nickname template. Sender mode chooses `inbox-slug@domain` or `email-username@domain`. Users who can reply in the category can edit their email username, email nickname and plain-text signature independently. The email username defaults to the forum username (lowercase). The email nickname defaults to the forum nickname, or the forum username if no nickname is set. Clearing a custom email nickname restores the forum nickname. Saved email usernames are preserved on upgrade. Usernames remain validated and unique; personal email identity changes do not change the forum profile.

The global `shared_inbox_nickname_template` site setting defaults to `{user_nickname}`. For example, `{user_nickname} @ XXX` sends as `Alice @ XXX <alice@domain>`. An Inbox can override this template; leave its template blank to inherit the global setting. Templates apply to the sender display name in both sender-address modes. Supported placeholders are `{user_nickname}` (effective email nickname), `{user_username}` (effective email username), `{inbox_name}` and `{inbox_slug}`. Templates use plain placeholder substitution, with no executable code. Unknown placeholders, control characters and templates longer than 255 characters are rejected. Existing queued messages keep their original sender snapshot.

An Inbox can be renamed or deleted only while unused. Disable an Inbox that already has conversations. Re-enabling resumes queued outbound delivery if it remains inside the idempotency window.

Inbox tags identify imported topics. The database association determines recipients; adding a tag to an arbitrary topic does not start emailing it, and removing a tag does not switch the recipient. One incoming email addressed to multiple Inboxes creates one conversation per Inbox. Untagged/unrecognized recipient addresses are acknowledged and ignored. New conversations require a configured, enabled Inbox.

## Sending and threading

Only newly created public regular replies in imported topics in the configured category are queued. First posts, whispers, moderator/small-action posts, posts with an action code, imported emails, deleted/hidden/empty posts, staged/system users and users without category access are excluded. The worker rechecks eligibility before sending. Editing a post does not send another email. Outbound payloads, including signature and sender, are captured when the reply is created so retries use the same content.

Replies use the original subject with `Re:`, `In-Reply-To` and `References`. The external email's Reply-To (or From) is the recipient; there is no automatic Reply All or forwarding of Discourse watchers. A tokenized `Reply-To` of `inbox-slug+<opaque-token>@domain` routes further replies even if an email provider rewrites Message-ID. The visible From remains the selected Inbox/user address. Resend receiving must accept these plus addresses. Each incoming follow-up must match both the Inbox and the original sender before it can join an existing topic. Different senders create separate topics, even with the same subject. References alone never grant access to a conversation. As with email generally, this does not provide cryptographic authentication of the sender.

When the Inbox setting is enabled, the presence of either `List-Unsubscribe` or `Unsubscribe` skips the incoming email entirely. Auto-generated messages (`Auto-Submitted` other than `no`) and the plugin's own `X-Shared-Inbox: 1` messages are ignored to prevent loops. Only `email.received` Webhook events are imported.

Closing or archiving an imported topic adds `[Closed] ` once. The prefix disappears when both closed and archived are false. Email subjects remain unchanged. Status action posts are never emailed. Follow-up incoming emails can be added to an existing closed/archived conversation without reopening it.

## Content and attachments

Incoming plain text, or text extracted from HTML, is displayed in an escaped code block. Email HTML, remote tracking images, mentions, scripts and oneboxes are not rendered. Messages exceeding Discourse's post length limit are truncated. Original messages remain in Resend.

**This version lists incoming attachment filenames but does not import binary attachments.** Retrieve originals in Resend. Discourse replies are sent as HTML and plain text; links use Discourse's normal email formatting. Uploads are not attached as MIME files; private/secure upload links remain subject to Discourse's access controls. The plugin does not implement forwarding, arbitrary new outbound conversations, delivery-status synchronization or email-based unsubscribe actions.

## Operations and recovery

Signed Webhooks are checked against the exact raw body, with a five-minute timestamp window and a 256 KiB request limit. The endpoint works on login-only forums and does not require cookies or CSRF tokens. A durable event record is stored before the job is queued. Email-ID/Message-ID constraints and an Inbox lock make duplicate imports safe. The post, topic, tag and deduplication record commit together.

Outbound replies use a durable outbox, a per-post unique key and Resend's `Idempotency-Key`. The first attempt timestamp is committed before the network request. A scheduled job runs every five minutes to recover pending work after process/Redis failures. Network/5xx/429 errors remain pending; other 4xx failures require an administrator retry after fixing configuration. The settings page displays the latest 50 unsent deliveries and 20 pending incoming events. Error codes are displayed without provider response bodies or credentials. `sent` means accepted by Resend, not guaranteed delivered to the recipient.

Resend stores idempotency keys for 24 hours. This plugin stops automatic retries at 23 hours and marks the delivery **Needs review**. It will not offer an unsafe new send after that window. Inspect Resend logs before deciding whether a manual email is appropriate. A domain change stops existing conversations from sending under the old domain. Existing queued payloads are immutable; changing identity/signature affects later replies.

Avoid moving imported topics out of the receiving category if you intend to continue the email conversation. A moved/deleted topic will not send further replies; new incoming messages start a new topic. Disabling the plugin pauses processing and returns 404 to new Webhooks; disabling an Inbox stops matching new mail while its queued deliveries pause. Webhooks for unknown/disabled Inboxes and ignored headers are acknowledged and are not replayed automatically after configuration changes.

The plugin adds six `shared_inbox_*` tables. Include them with normal Discourse database backups. Email bodies in posts and outbound payloads in the outbox inherit your database backup/retention policy. Uninstalling the plugin does not remove data or drop tables.

## Tests

The independent behavior suite uses the shipping migration/models/services/controllers and an in-memory SQLite database. Small adapters represent Discourse's APIs; it does not replace tests on a full Discourse installation.

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle install
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec rspec test/standalone
```

Run the native host integration suite in a configured Discourse checkout after migrations:

```sh
LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-shared-inbox-resend/spec
```

See [VALIDATION.md](VALIDATION.md) for exactly what was executed for this release.

## License

MIT. See [LICENSE](LICENSE).
