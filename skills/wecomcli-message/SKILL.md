---
name: wecomcli-message
version: 1.2.0
risk_level: high
type: procedural
status: enabled
description: 查询当前可以发送消息的聊天会话范围，并向会话列表中的单聊或群聊发送文本、Markdown、图片、文件、语音、视频消息。用户要求“给某人发消息”“在某个群里通知”“给最近会话发消息”或“把图片/文件/语音/视频发到企业微信”时使用。
metadata:
  requires:
    bins: ["wecom-cli"]
---

# 企业微信发送消息

> 执行任何 `wecom-cli` 命令前，必须先读取并完成 `wecom-shared` 技能的公共前置检查。

1. 可以向授权人发送消息。
2. 可以向授权人以外的、机器人最近有消息往来的聊天会话（单聊和群聊）发送消息。

## 适用范围

### 适用

- 适用于给授权人发消息，使用 `wecom-cli identity whoami` 获取授权人ID，可作为 `chat_id` 使用，无需调用 `sessions list`。
- 适用于查询当前有权限发送消息的聊天会话范围并给这些范围中的成员或群聊发送 Markdown 消息、图片、文件、AMR 语音或视频
- 适用于以**授权人本人身份**（非机器人身份）发送纯文本消息 —— `message send`，DesireCore 增补，见下方专节
- 适用于按 `media_id` 把聊天消息里的图片 / 文件 / 语音 / 视频取回本地 —— `message files get`，DesireCore 增补，见下方专节

### 不适用

- 发送对象不是授权人且不在本次 `sessions list` 返回结果中 → 告知用户当前只能向最近活跃的会话或授权人发送

## 技能依赖

调用依赖技能前，必须先完整读取对应 `SKILL.md`。

| 依赖技能 | 触发场景 | 数据流向 |
|---|---|---|
| `wecomcli-media` | 发送图片、文件、语音或视频时只有本地文件路径，没有可直接复用的 `media_id` | 包含媒体上传接口，如没有已有的 `media_id`，必须先阅读该技能获取 `media_id`，上传时传入的 `type` 应和发送时的`msg_type` 对齐|

## 获取能发送消息的会话列表

### 命令

```bash
wecom-cli message aibot sessions list
```

### 返回

| 字段 | 类型 | 说明 |
|---|---|---|
| `sessions` | array | 会话列表，按最后一条消息时间从新到旧排序，具体数量以实际回包为准 |
| `sessions[].chat_id` | string | 会话 ID |
| `sessions[].chat_name` | string | 群名称或单聊名称 |
| `sessions[].chat_type` | string | `single` 单聊或 `group` 群聊 |
| `sessions[].last_msg_time` | string | 最后一条消息时间，格式 `YYYY-MM-DD HH:MM:SS` |
| `sessions_count` | integer | `sessions` 数组元素数量 |

### `chat_id` 来源

向授权人以外的用户发送消息，调用 `wecom-cli message aibot send` 前，需要先调用一次 `sessions list`，然后从本次返回的 `sessions[]` 中选定目标项，把该项的 `chat_id` 原样复制到 `send.chat_id`。

以下值都不能直接作为 `send.chat_id`：

- 用户输入的 ID
- 之前轮次或历史上下文保存的 `chat_id`
- `wecomcli-contact` 返回的 `userid`
- 根据姓名、群名或其他字段自行构造的值

这些值最多只能作为匹配线索；最终发送参数必须重新取自本次 `sessions list` 的匹配项。

### 目标会话匹配

- **聊天名称**：在本次 `sessions[]` 中按非空 `chat_name` 精确匹配；不能精确匹配需要向用户反问确认发送目标，唯一命中时从匹配项复制 `chat_id`。
- **最近第一个/最近某个会话**：按 `sessions[]` 原始顺序选择用户明确指定的项。
- **用户提供 ID**：只能与本次 `sessions[].chat_id` 做完全相等校验；命中后仍从匹配项复制 `chat_id`，不能直接复用用户输入值。

匹配结果处理：

- 唯一匹配时继续发送。
- 多个聊天会话候选时，按返回顺序展示聊天名和最后消息时间，让用户选择。
- 用户完成选择后，必须重新调用 `sessions list`，再用选定对象匹配当次返回值。
- 无匹配时停止发送，如实告知目标不在最近 10 个会话中；不要接受外部 `chat_id` 绕过限制。
- `sessions_count=0` 时停止发送，告知当前没有可发送的最近会话。
- 展示会话列表时保持接口原始顺序；展示名称和时间，不展示内部 `chat_id`。

## 发送消息

### 前置条件

调用本接口前必须完成以下步骤：

1. 根据发送对象选择调用 `wecom-cli message aibot sessions list`获取 `chat_id` 或 `wecom-cli identity whoami` 获取授权人ID。
2. 在本次列表中唯一匹配目标。
3. 如果发送授权人以外的对象，从列表中匹配项原样复制 `sessions[].chat_id`。
4. 目标是媒体消息时，再准备对应的 `media_id`。

在目标会话匹配成功前，不上传媒体，也不调用 `send`。

### 命令

```bash
wecom-cli message aibot send --json '<JSON 参数>'
```

### 公共参数

| 字段 | 类型 | 必填 | 说明 |
|---|---|:---:|---|
| `chat_id` | string | 是 | 必须取自 `wecom-cli identity whoami` 或当前发送流程中刚调用的 `sessions list` 返回的目标 `sessions[].chat_id` |
| `msg_type` | string | 是 | `markdown` / `image` / `file` / `voice` / `video` |
| `markdown` | object | 条件必填 | 仅 `msg_type="markdown"` 时传 |
| `image` | object | 条件必填 | 仅 `msg_type="image"` 时传 |
| `file` | object | 条件必填 | 仅 `msg_type="file"` 时传 |
| `voice` | object | 条件必填 | 仅 `msg_type="voice"` 时传 |
| `video` | object | 条件必填 | 仅 `msg_type="video"` 时传 |

每次请求必须且只能携带一个与 `msg_type` 同名的内容对象。不要传空对象，也不要同时传多个消息对象。

### Markdown 消息

`markdown.content` 必填，最长 20480 UTF-8 字节。普通文本也按 Markdown 发送。

```bash
wecom-cli message aibot send --json '{
  "chat_id": "<本次 sessions[].chat_id>",
  "msg_type": "markdown",
  "markdown": {
    "content": "<markdown 消息内容>"
  }
}'
```

### 图片消息

`image.media_id` 必填，必须由媒体上传接口以 `type=image` 上传获得。

```bash
wecom-cli message aibot send --json '{
  "chat_id": "<本次 sessions[].chat_id>",
  "msg_type": "image",
  "image": {
    "media_id": "<media_id>"
  }
}'
```

### 文件消息

`file.media_id` 必填，必须由媒体上传接口以 `type=file` 上传获得；文件名取上传时的原始文件名。

```bash
wecom-cli message aibot send --json '{
  "chat_id": "<本次 sessions[].chat_id>",
  "msg_type": "file",
  "file": {
    "media_id": "<media_id>"
  }
}'
```

### 语音消息

`voice.media_id` 必填，必须由媒体上传接口以 `type=voice` 上传获得；源文件仅支持 AMR 格式，不能只改扩展名冒充 AMR。

```bash
wecom-cli message aibot send --json '{
  "chat_id": "<本次 sessions[].chat_id>",
  "msg_type": "voice",
  "voice": {
    "media_id": "<media_id>"
  }
}'
```

### 视频消息

| 字段 | 必填 | 说明 |
|---|:---:|---|
| `video.media_id` | 是 | 由媒体上传接口以 `type=video` 上传获得 |
| `video.title` | 否 | 最长 128 UTF-8 字节；省略时使用上传时的原始文件名 |
| `video.description` | 否 | 最长 512 UTF-8 字节；省略时不展示描述 |

```bash
wecom-cli message aibot send --json '{
  "chat_id": "<本次 sessions[].chat_id>",
  "msg_type": "video",
  "video": {
    "media_id": "<media_id>",
    "title": "产品演示",
    "description": "本周版本的核心功能演示"
  }
}'
```

用户没有提供视频标题或描述时直接省略对应字段，不传空字符串，也不追问非必填字段。

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

## 取回聊天消息里的媒体 —— `message files get`（DesireCore 增补）

> 本节是 DesireCore 对上游 `wecomcli-message` 的增补：上游 14 个技能全文没有一次用到
> `message.files.get`，本节参数已按 `wecom-cli 1.2.0` 的
> `wecom-cli message files get --schema` 逐字段核对。风险等级：**read（只读）**。

消息列表里的 `image` / `file` / `voice` / `video` 各带一个 `media_id`，用它把内容取下来：

```bash
wecom-cli message files get --media-id '<消息里的 media_id>'
```

### 参数

| 字段 | 类型 | 必填 | 说明 |
|---|---|:---:|---|
| `media_id` | string | 是 | 长度 1–256；取自消息列表返回的 `image` / `file` / `voice` / `video.media_id` |

### 返回 `media_item`

| 字段 | 说明 |
|---|---|
| `media_type` | `image` / `file` / `voice` / `video` |
| `file_name` | 媒体文件名（含扩展名）—— **这是可以展示给用户的可读信息** |
| `content` | 内容不长时直接返回的字符串 |
| `file_path` | 内容超长或含非 UTF-8 字节时由框架落盘，改用此字段返回**本地文件路径** |
| `media_id` | 与请求入参一致 |

**`content` 与 `file_path` 是二选一的**：小内容走 `content`，大内容 / 二进制走 `file_path`。
处理时两个都要判。想固定落盘可加 `-o <file>` 或 `--output-dir <dir>`。

**`file_path` 属于禁露字段**：告诉用户「已取到文件『周报.pdf』」，不要把本地路径贴出来。

> ⚠️ **别和 `media download` 搞混**（两者都叫 `--media-id`，但 `media_id` 来源不同）：
>
> - `message files get --media-id` 取的是**聊天消息里的**媒体，`media_id` 来自消息列表返回的
>   `image` / `file` / `voice` / `video.media_id`。
> - `media download --media-id`（见 `wecomcli-media`）取的是**由 CLI 上传后获得的** `media_id`
>   （schema 原文：「由 CLI 上传文件后获得」，框架层会把它解码为 cosid）。
>
> 两者解码路径不同，互换很可能失败（**未实测**，但 schema 描述明确指向不同来源）。
> 拿到 `media_id` 时记住它是从哪个接口来的，用配套的方法取。

## 关键约束

- 用户明确要求发送且目标与内容完整时直接执行，不重复追问确认；缺少目标、内容或本地文件时只追问缺失项。
- 连续发送多条时，不用每次 `send` 前都重新调用 `sessions list` 或 `wecom-cli identity whoami`，但连续发送中途上下文发生压缩时重新调用确保 `chat_id` 正确。
- `chat_id`、`userid`、`media_id` 都是内部调用值，禁止面向用户展示。
- Markdown 正文、视频标题和描述限制按 UTF-8 字节数计算；超限时不静默截断，请用户缩短或明确同意拆分。
- 发送成功后只说明目标和消息类型，不编造消息 ID。
- 接口失败时如实转达错误，不使用 curl / Python 等方式绕过 `wecom-cli`。
