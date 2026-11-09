# Release validation / 版本验证

Date: 2026-11-09.

## Executed

- **71 independent behavior examples passed, 0 failures.** Executed using Ruby 3.4, ActiveRecord/ActionPack 7.2.3, RSpec, WebMock and SQLite, using the dependency lockfile in `test/standalone`.
- The shipping PostgreSQL migration was executed against SQLite with a test-only `jsonb` → `json` adapter. The actual Inbox/Profile/Conversation/Message/Event/Delivery models were loaded.
- Actual inbound/outbound services, policy, title synchronizer, HTTP client and stateless Webhook controller were tested. Host APIs such as PostCreator, Guardian and PrettyText use small adapters in this independent suite.
- Coverage includes raw-body Svix verification, expiry, rotated signatures, malformed and oversized requests; full-email retrieval; duplicate events/messages; Inbox and sender isolation; reply-token routing; Unsubscribe filtering; transactional import rollback; real-reply filtering; immutable outbound payloads; fixed idempotency keys; process/database failure recovery boundaries; provider failures; domain changes; title close/archive transitions; profile validation and safe content rendering.
- All **31 Ruby files** passed `ruby -c`.
- All **5 JavaScript/GJS files**, including embedded Glimmer templates, parsed using `content-tag`, `@babel/parser` and `@glimmer/syntax`. Frontend files were formatted with Prettier's Ember template-tag plugin.
- YAML parsed successfully. English/Simplified Chinese translation key sets matched: **13 server keys and 33 client keys** per locale.
- The Git bundle was verified and cloned into a fresh checkout. Git integrity and branch/tag contents were checked.

## Not executed

- The full Discourse application, PostgreSQL integration, browser interaction and Discourse's native host integration suite were **not executed** in this environment. The supplied `spec/requests/shared_inbox_spec.rb` covers real PostCreator hooks, custom-field persistence, whispers, status changes, login-only Webhooks and category/admin authorization for running inside a configured Discourse checkout.
- No live Resend credentials or configured receiving domain were supplied. Actual DNS, receiving, API sending and grouping in external email clients need a staging smoke test with the deployment's domain.

The plugin targets Discourse 3.5+ APIs. Implementation was cross-checked against Discourse source revision `f00f07d6` and Resend's received-email and reply-to-email API documentation. Static parsing does not establish full frontend runtime compatibility across Discourse versions.

中文：已通过 71 项独立行为测试、Ruby/前端模板语法检查和中英翻译键检查。独立测试使用实际插件代码，Discourse 侧接口使用测试适配器；尚未运行完整 Discourse、PostgreSQL 和浏览器集成测试，也未进行真实 Resend 收发联调。仓库已附真实 Discourse 请求集成测试，部署前请在目标版本的测试环境执行。入站附件仅列文件名，不导入二进制文件，详见中英 README。
