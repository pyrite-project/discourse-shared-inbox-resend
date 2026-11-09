# Shared Inbox with Resend

[English documentation](README.md)

将 Discourse 类别变成由 Resend 提供收发能力的共享收件箱。需要 Discourse 3.5+、PostgreSQL、Redis/Sidekiq，并启用 Discourse 标签。界面、站点设置及插件错误信息支持英文和简体中文。

## 安装

标准 Docker 部署：在 `/var/discourse/containers/app.yml` 现有 `after_code` 插件克隆命令列表中加入：

```yaml
- git clone https://github.com/pyrite-project/discourse-shared-inbox-resend.git
```

然后在 `/var/discourse` 中重建：

```sh
./launcher rebuild app
```

已有 Discourse 开发环境时，在 Discourse 根目录执行：

```sh
git clone https://github.com/pyrite-project/discourse-shared-inbox-resend.git plugins/discourse-shared-inbox-resend
bundle exec rake db:migrate
```

随后按当前安装方式重建前端资源，并重启 Web 和 Sidekiq 进程。 升级到 1.1.0 时需执行新增的邮件昵称和 Inbox 模板数据库迁移；Docker 部署可通过重建完成。

## 配置步骤

1. 在 Resend 配置域名或专用子域名，设置接收用 MX 和发信用 SPF/DKIM，确保同时启用接收和发送。已有公司邮箱时，宜使用专用子域名。
2. 创建邮件接收类别，为预期的客服团队授予查看及回复权限，并启用站点标签功能。导入的邮件继承此类别的可见性。
3. 在 **管理 → 站点设置** 的 **Shared Inbox with Resend（共享收件箱）** 分组中填写（也可搜索 `shared_inbox`）：

   | 设置 | 内容 |
   | --- | --- |
   | `shared_inbox_domain` | 例如 `inbox.example.com`，不含 `@`、协议或路径 |
   | `shared_inbox_category_id` | 邮件接收类别 |
   | `shared_inbox_nickname_template` | 全局发件人昵称模板，例如 `{user_nickname} @ XXX` |
   | `shared_inbox_resend_api_key` | 可读取接收邮件并发送邮件的 Resend API Key |
   | `shared_inbox_webhook_secret` | Webhook 的 `whsec_...` 签名密钥，不是 API Key |
   | `shared_inbox_enabled` | 配置完成后启用 |

4. 在 Resend 新建 Webhook：`https://你的论坛/shared-inbox/webhook`，订阅 **`email.received`**；复制该 Webhook 的签名密钥到上述设置。子目录部署时带上论坛的基础路径。反向代理需保留原始请求体和 `svix-id`、`svix-timestamp`、`svix-signature` 请求头。
5. 打开接收类别，点击 **Shared Inbox with Resend**。管理员可新建 Inbox，例如 `support` 对应 `support@inbox.example.com`，`sales` 对应 `sales@inbox.example.com`。也可直接访问 `/shared-inbox-settings`。
6. 用外部邮箱发一封测试邮件，确认出现带 `inbox-support` 标签的话题；公开回复应回到原邮件线程。再验证密语、关闭、归档和恢复。

插件未启用时，管理员也可以看到全部六项站点设置。可直接访问 `/admin/site_settings/category/discourse_shared_inbox_resend`。默认安装目录为 `discourse-shared-inbox-resend`。已有的 `shared-inbox-with-resend` 目录无需重命名，其设置分组仍为 `shared_inbox_with_resend`。插件设置页面、后台筛选参数与设置归属统一使用实际安装目录标识。更新插件后请重启或重建 Discourse，并刷新后台页面。

用户设置页不接收 Resend 凭据。API Key 和 Webhook 签名密钥仅供服务端使用，不下发给客户端。

## Inbox 和个人设置

每个 Inbox 可配置启用状态、是否忽略退订头、发件人昵称模板，以及发件地址模式：

- Inbox 模式：`<inbox-slug>@<domain>`。
- 用户模式：`<email-username>@<domain>`。

拥有类别回复权限的用户可在类别入口分别修改邮件 username、邮件 nickname 和纯文本签名。邮件 username 默认使用论坛 username（转换为小写），邮件 nickname 默认使用论坛 nickname；未设置论坛昵称时使用论坛 username。清空自定义邮件 nickname 后恢复论坛昵称。升级时保留已有的邮件 username 设置。邮件身份设置不修改论坛个人资料。邮件 username 仍须唯一，并使用小写字母、数字、点、下划线或连字符。

全局站点设置 `shared_inbox_nickname_template` 默认是 `{user_nickname}`。例如设置为 `{user_nickname} @ XXX`，发件人显示为 `Alice @ XXX <alice@domain>`。Inbox 可以单独设置模板，留空时继承全局设置；模板优先级为 **Inbox → 全局 → `{user_nickname}`**。模板在两种发件地址模式下都生效，仅影响发件人显示名。支持 `{user_nickname}`（实际邮件昵称）、`{user_username}`（实际邮件用户名）、`{inbox_name}` 和 `{inbox_slug}`。模板仅进行占位符替换，不执行代码；不支持的占位符、控制字符和超过 255 个字符的模板会被拒绝。已入队邮件保留创建时的身份快照。

未使用的 Inbox 可修改 slug 或删除。已有邮件话题的 Inbox 请停用；重新启用后，尚在幂等保护窗口内的待发邮件会继续处理。

标签用于识别 Inbox，数据库关联决定实际收件人。仅给普通话题添加标签不会触发发信；删除或修改标签也不会切换原话题的邮件收件人。同一封邮件发往多个 Inbox 时，每个 Inbox 各建一个话题。未知或已停用地址会被确认接收后忽略。

## 回复和线程行为

仅在已导入话题中，新建的真实公开普通回复会进入发件队列。首帖、密语、系统操作、小操作记录、带操作代码的帖子、导入邮件、已删/隐藏/空白帖子、系统或暂存用户，以及无访问权限用户的帖子均不会发送。发送前再次检查帖子和类别权限。编辑帖子不会再次发信；重试使用创建回复时保存的正文、身份和签名快照。

回复保持原主题并使用 `Re:`、`In-Reply-To` 和 `References`。收件人使用原邮件的 Reply-To，没有时使用 From。不自动执行 Reply All，不把 Discourse 关注者加入收件人。

邮件的可见 From 使用所选用户或 Inbox 地址。Reply-To 使用 `inbox-slug+<随机线程标识>@domain`，使邮件服务商重写 Message-ID 后的后续来信仍能关联到线程。Resend 接收域名需支持这些加号地址。来信必须同时匹配 Inbox 和原发件人才能追加到已有话题；仅同主题不合并，不同发件人会新建话题。此关联规则不等于对发件人身份的密码学认证。

启用 Inbox 的退订头过滤时，只要存在 `List-Unsubscribe` 或 `Unsubscribe`，就整封忽略。带非 `no` 的 `Auto-Submitted` 头的自动邮件，以及带插件自身 `X-Shared-Inbox: 1` 标记的邮件会被忽略，以防循环。仅导入 `email.received` 事件。

关闭或归档已导入话题后，标题添加一次 `[Closed] `；只有关闭和归档状态都解除后才移除。邮件的原主题不受影响。后续来信可追加到关闭/归档的话题，不会自动重新打开。

## 正文和附件

入站邮件优先使用纯文本，没有纯文本时从 HTML 提取文字，以安全代码块展示，避免执行脚本、显示跟踪图片、生成提及或 onebox。超过 Discourse 帖子长度限制的正文会截断；原邮件保留在 Resend。

**此版本展示入站附件文件名，不将附件二进制文件导入 Discourse。** 原附件请在 Resend 查看。出站回复包含 HTML 和纯文本，链接使用 Discourse 的邮件格式化逻辑；不会将帖子上传文件转换成 MIME 附件，私密/安全上传链接仍受论坛访问控制。此版本不包含转发、从零创建出站会话、投递状态同步或执行邮件退订操作。

## 运维与重试

Webhook 按原始请求体验证签名，允许五分钟时间偏差，请求体限制为 256 KiB；私密论坛也无需登录、Cookie 或 CSRF Token。先持久化事件，再排队处理。Email-ID、Message-ID 唯一索引和 Inbox 数据库锁防止重复导入；帖子、话题、标签和去重记录在同一事务提交。

出站使用持久化队列、每帖唯一记录和 Resend `Idempotency-Key`。第一次尝试的时间在调用发送 API 前单独提交，避免进程或数据库异常重置幂等计时。每五分钟自动恢复未完成任务。网络、5xx、429 错误自动重试；其他 4xx 错误需管理员修复配置后重试。

管理员可在设置页查看最近 50 条未发送记录和 20 条待处理来信事件。界面显示错误码，不显示供应商响应正文或凭据。已发送表示 Resend 已接受请求，不保证收件人的邮件服务器最终投递成功。

Resend 幂等键有效期为 24 小时。插件在 23 小时后停止自动重试，标记为「需要检查」，并阻止不安全的重发。此时请先核对 Resend 日志，再判断是否需要人工发送。更换域名会阻止旧域名会话继续发信；修改个人签名或身份只影响后续新回复。

将话题移出接收类别后不会继续对外发送回复，后续来信会新建话题。停用插件时暂停处理，新 Webhook 返回 404；停用 Inbox 时忽略新的匹配来信并暂停其待发队列。已确认忽略的未知/停用 Inbox 邮件，以及按邮件头过滤的邮件，不会在修改设置后自动重放。

插件新增六张 `shared_inbox_*` 表，应随 Discourse 数据库一起备份。邮件正文保存在帖子中，待发快照保存在发件队列表中，遵循数据库的备份及保留策略。卸载插件不会自动删除帖子或数据库表。

## 测试

独立行为测试运行实际的迁移、模型、服务、Webhook 控制器和 HTTP 客户端，数据库使用内存 SQLite，Discourse 侧 API 使用小型适配器。这些测试不能替代真实 Discourse 安装中的集成测试。

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle install
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec rspec test/standalone
```

真实 Discourse 测试环境执行迁移后：

```sh
LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-shared-inbox-resend/spec
```

本次实际验证范围详见 [VALIDATION.md](VALIDATION.md)。

## 许可证

MIT，见 [LICENSE](LICENSE)。
