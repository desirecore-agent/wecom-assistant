## 以授权人身份发纯文本 —— `message send`（DesireCore 增补）

> 本节是 DesireCore 对上游 `wecomcli-message` 的增补：上游 14 个技能全文没有一次用到
> `message.send`，本节参数已按 `wecom-cli 1.2.0` 的 `wecom-cli message send --schema` 逐字段核对。

### 🔴 先读这一段再决定要不要用

**实测结论（2026-09-03，DesireCore 测试企业）：本方法返回 `853006`
`this tool is not available for your corporation`** —— 是**整个企业不具备该能力**，
不是机器人权限问题；同一账号的 `message aibot send` 可以正常发送。

⇒ **默认且优先使用 `message aibot send`。** 遇 `853006` 直接向用户说明该企业未开通此能力，
**不要重试、不要换参数再试、不要绕道 curl / Python**。

⚠️ 本方法的**实际发送身份**（收件人看到是谁发的）与**可达目标范围**均**未经成功验证**
（上游零覆盖，schema 无明文）。它是对外发送、发错不可撤回。因此：
只有当用户**明确要求「不以机器人身份发送」**，且你**已如实告知这条路径未经验证**并取得同意后，
才可以调用。

> 「目标不在 `sessions list` 范围内」**不是**切换到本方法的理由 —— 那种情况应如实告知用户
> 「对方不在机器人最近的会话范围内，需要对方先给机器人发一条消息」。

### 强制交叉校验

调用 `message send` 之前，**必须先跑一次 `wecom-cli message aibot sessions list`**：

- 目标**命中** sessions list → **改用 `message aibot send`**（已验证路径优先，不要用本方法）
- 目标**未命中** → 向用户复述并取得明确同意后才继续：
  「该目标不在机器人会话范围内，将以非机器人身份发送，且这条路径未经验证，仍要发吗？」

### `chat_id` 的合法来源

| 会话类型 | 合法来源 | 附加要求 |
|---|---|---|
| 单聊 | `wecomcli-contact` 解析出的对方 `userid` | 用户在**本轮对话里逐字确认过收件人姓名** |
| 群聊 | `chat groups list` 返回的 `chats[].chat_id` | 用户在**本轮对话里逐字确认过群名** |
| 授权人本人 | `wecom-cli identity whoami` | — |

同样**禁止**：用户直接给的 ID、历史上下文缓存的 ID、按姓名或群名自行拼出来的值。

### 命令

```bash
wecom-cli message send --json '{
  "chat_id": "<按上表取得的会话 ID>",
  "msg_type": "text",
  "text": { "content": "会议改到明天下午三点。" }
}'
```

等价的 flag 写法：

```bash
wecom-cli message send \
  --chat-id '<会话 ID>' \
  --msg-type text \
  --text '{"content":"会议改到明天下午三点。"}'
```

### 参数

| 字段 | 类型 | 必填 | 说明 |
|---|---|:---:|---|
| `chat_id` | string | 是 | 单聊传接收成员的 `userid`，群聊传群会话 ID |
| `msg_type` | string | 是 | schema enum **只有 `text`**，传别的值必定失败 |
| `text` | object | 条件必填 | `msg_type=text` 时必填；`--help` 不标 `[必填]`，但不传**必定失败** |
| `text.content` | string | 是 | 上限 **2048 字符**（注意是字符，与 markdown 的 20480 **字节**口径不同） |

### 返回

返回体**没有任何业务字段**（schema 原文：成功与否由框架外壳的 `errcode` / `errmsg` 表达）。
因此**不要编造消息 ID**，发送成功后只说明目标与消息类型。

