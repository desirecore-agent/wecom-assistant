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

