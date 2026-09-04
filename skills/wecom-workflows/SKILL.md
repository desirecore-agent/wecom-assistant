---
name: wecom-workflows
description: >-
  企业微信跨产品编排。Use when 用户要的东西需要串起两个以上企业微信产品——晨间简报（日程+会议+待办+未读邮件）、
  会议闭环（纪要→待办→文档归档→跟进日程）、约会闭环（查共同空闲→订会议室→建日程或会议→通知参会人）、
  文档协作开场（新建文档→加协作成员→发消息通知）、逾期待办巡检并提醒（待办→消息）。
  本技能只提供三样东西：步骤顺序、跨步骤的确认拆分、中途某步失败时的降级处置（不能留下半成品还不告诉用户）。
  它**不重复**各单产品技能的参数形状与固定措辞——具体命令、必填项、日程/会议消歧问法一律回到对应技能的 SKILL.md 现查。
  单产品内的操作不用本技能，直接走对应技能：日程与会议室 wecomcli-calendar、在线会议与纪要 wecomcli-meeting、
  待办 wecomcli-todo、发消息 wecomcli-message、邮件 wecomcli-email、文档搜索/改名/权限 wecomcli-doc-manage、
  智能文档 wecomcli-smartpage、在线文档 wecomcli-doc、在线表格 wecomcli-sheet、智能表格 wecomcli-smartsheet、
  微盘 wecomcli-disk、通讯录 wecomcli-contact、媒体文件 wecomcli-media、群聊记录 wecom-chat；
  CLI 安装/授权前置检查与全局铁律见 wecom-shared。
version: 1.0.0
type: procedural
risk_level: high
status: enabled
tags:
  - wecom
  - workflow
  - orchestration
---

# 企业微信跨产品编排

**只有跨 ≥2 个企业微信产品时才用本技能。** 单产品内的复合任务（批量建待办、建完文档就写正文、
建完表格就填数据）各自的 `wecomcli-*` 技能已经写全，直接用它们。

本技能存在的理由只有一条：**跨产品链路里，中途失败会留下半成品**——待办建了一半、日程建好了但
没人知道、文档发出去了但对方打不开。单产品技能只对自己那一步负责，没有人对「这条链路整体交付了
什么」负责，本技能补的就是这个位置。

> **前置**：每条 recipe 都以 `wecom-shared` 的前置检查为起点（CLI 已装、版本达标、`auth show --status` 返回 `authorized`），未通过时一步都不执行。

## 共用执行纪律

**1｜先探可用性再编排。** 每条 recipe 开始前用只读命令把依赖的产品各探一次。遇
`850002`（品类未授权）/ `851008`（部分未授权）/ `853006`（企业级不可用）：**不重试、不换方法绕**，
把响应里的 `help_message` **逐字原样**转达，再告诉用户「这条链路缺 X，要么跳过这一步、要么换个做法」。
已实测为 `853006` 的有 `message send` 与 `chat groups list`——编排里发消息一律走 `message aibot send`。

**2｜台账是强制的。** 任何一步失败都不能静默跳过，最后如实汇报每步 `ok` / `skipped` 及原因。**不要**把 `skipped` 写成 0，**不要**把不确定写成确定。

**3｜一次确认只覆盖一步写操作。** 这是编排层最容易违规的地方。❌「我会把纪要建成待办、写成文档、
再发群里通知，可以吗？」——一句「好」吞掉三步。✅ 先只确认建待办，建完再单独确认发通知；中间的
write-low 步骤（建文档、建文件夹）直接做完汇报。用户说「后面都按你说的来」时，仍要把剩下每一步的
具体影响列一遍再执行，不接受空白授权。

**4｜ID 只在流程内传递。** 前一步返回的 `meeting_id` / `docid` / `userid` / `chat_id` 直接喂给下一步，
不重新"想"一个，也不用姓名当标识符。回复只出现姓名、群名、文档标题、会议主题。

**5｜机器人只能改自己创建的数据。** 链路里某步要改**真人**建的日程/文档/待办时，
**提前**说明边界并给替代方案（「由我新建一份」或「这步你自己在客户端改」），别跑到那步才失败。

**6｜「待办」≠「全部待办」。** `todo list` 的官方描述是「读取**机器人为创建人**、对话人为参与人的待办
列表」，天然不含用户自己建的待办。汇报时说「我这边能看到的待办」，**禁止**说成「你全部的待办」。

## Recipe 1 · 晨间简报

**触发语**：「今天有什么安排」「早上给我个汇总」「今天要处理什么」
**跨产品**：calendar + meeting + todo + mail　**性质**：纯只读，可安全自动执行

```bash
wecom-cli calendar schedules list --begin-time '2026-09-04 00:00:00' --end-time '2026-09-04 23:59:59'
wecom-cli meeting list --begin-time '2026-09-04 00:00:00' --end-time '2026-09-04 23:59:59'
wecom-cli todo list --json '{"status_filter":["proceed"],"limit":20}' --page-count 10
wecom-cli mail search --json '{"only_unread":true,"limit":20}' --page-count 5
```

**汇总顺序**：已逾期待办 > 今日日程与会议（按开始时间升序）> 今日到期待办 > 未读邮件。日程给
时间+主题，待办给截止时间，邮件只给发件人+主题+时间。

**已知失败态与降级**

- 前两步是同一问题的两半：日程返回里 `meeting.meeting_code` 非空的条目会与 `meeting list` 重复，
  按「主题 + 时间」去重只留一条，末尾汇总「共 N 场」。
- `meeting list` **不返回参会人姓名**，要姓名得再 `meeting get`（一批 ≤10）；简报通常不需要参会人，
  **不要为了凑字段多调一轮**。
- `mail search` 带 `only_unread` 时范围**不超过最近 30 天**；`has_more` 为 true 时必须写明
  「已展示前 N 封（未拉完）」，别让用户以为这就是全部。
- 任一步失败 → 台账记 `skipped`，**其余步骤照常出结果**，不要一步失败就整条放弃。
- **默认只在对话里输出，不主动推送。** 用户要推送时按 Recipe 5 的发送纪律另走一次确认。

## Recipe 2 · 会议闭环（纪要 → 待办 → 归档 → 跟进）

**触发语**：「把昨天评审会的待办建起来」「这个会的纪要整理一下归档」「会后跟进安排一下」
**跨产品**：meeting → todo + smartpage + calendar　**性质**：建待办与建跟进日程各需一次独立确认

```bash
# 1 定位：有主题关键词走 search，只有时间走 list
wecom-cli meeting search --json '{"keywords":["项目评审"],"limit":20}'
# 2 取纪要与官方已抽取的待办 → 读 has_note_permission / notes[].note_content / notes[].todo_content
wecom-cli meeting get --json '{"meeting_ids":[{"meeting_id":"<meeting_id>"}]}'
# 3 仅当纪要不可用时兜底拉转写原文（has_more 为 true 必须翻页到底）
wecom-cli meeting original get --json '{"meeting_id":"<meeting_id>"}'
# 4 【确认后】建待办，单批 ≤20 条
wecom-cli todo create --json '{"items":[{"title":"补充 Q4 预算测算","follower_ids":["<userid>"],
  "deadline":{"type":"date","value":"2026-09-08"}}]}'
# 5 归档：本地写好 markdown 再导入成智能文档（write-low，可直接做）
wecom-cli smartpage import --json '{"file_path":"/abs/path/项目评审纪要.md","name":"项目评审会纪要"}'
```

**顺序上的硬约束**

- 第 2 步的 `notes[].todo_content` 是**官方已抽取好的行动项**，优先直接用；**不要自己从转写原文里
  "理解"出一套**——会和用户在企业微信里看到的不一致。只有 `notes` 为空或
  `has_note_permission == false` 时才走第 3 步。
- 第 4 步传 `follower_ids` = **把待办分派给他人并触发提醒**，属对外可见。执行前把「建哪几条、指派
  给谁、截止什么时候」**逐条列出**并取得同意。姓名先经 `wecomcli-contact` 解析，多候选必须问。

**中途失败的降级**

- 第 3 步成功但 `original_data` 为空 → 如实说「该会议暂无智能纪要，也无转写原文（可能未开启转写 /
  会议未开始 / 无发言记录）」，**不编造纪要**，链路到此为止。
- 第 4 步**部分失败**：返回的 `items[]` 每条各带 `success` / `errmsg`，**不能按整体成功判定**。失败
  条目把标题和 `errmsg` 原样列出，**不自动回滚已建成功的那些**（参与人可能已收到提醒），由用户定夺。
- 第 5 步失败：**先说待办已建好**，再说文档没归档。不要因为归档失败去删待办。
- 再排一场跟进会是**新的一次 write-high**，必须**另取一次同意**；若是把已有会议改期，
  一律走 `meeting update`，**禁止 cancel + create**（入会链接不可重建，拆开就永久丢失）。

## Recipe 3 · 约会闭环（查空闲 → 订会议室 → 建日程/会议 → 通知）

**触发语**：「约张三李四下周三下午碰一下，订个会议室」「大家什么时候都有空，定下来通知一声」
**跨产品**：contact + calendar（忙闲/会议室）+ calendar 或 meeting + message
**性质**：风险集中在「建了却没订到会议室」和「建了却没人知道」

```bash
# 1 姓名 → userid（多候选按姓名+部门让用户选）
wecom-cli contact users search --json '{"keywords":["张三"]}'
# 2 共同空闲：窗口 ≤24h，userids 是对象数组，必须把自己也算进去
wecom-cli calendar schedules free list --json '{"userids":[{"userid":"<me>"},{"userid":"<ta>"}],
  "begin_time":"2026-09-05 09:00:00","end_time":"2026-09-05 18:00:00","min_duration_minutes":60}'
# 3 仅当用户提到会议室；取 target[].room.meeting_room_id 且 status=bookable
wecom-cli meeting rooms search --json '{"begin_time":"2026-09-05 14:00:00",
  "end_time":"2026-09-05 15:00:00","room_name":"1605"}'
# 4 【确认后】一次建成（纯日程走 calendar；含入会链接的会议走 meeting create）
wecom-cli calendar schedules create --json '{"subject":"产品评审","begin_time":"2026-09-05 14:00:00",
  "end_time":"2026-09-05 15:00:00","attendees":[{"userid":"<ta>"}],"meeting_room_id":"<meeting_room_id>"}'
# 5 可选通知，按 Recipe 5 的发送纪律，需另取一次同意
```

> 创建场景「日程还是会议」的消歧问法**措辞逐字固定**，写在 `wecomcli-calendar` /
> `wecomcli-meeting` 里。本技能不重写也不改写——先读那两份 SKILL.md 再问。

**中途失败的降级**

- 第 2 步**查到冲突** → 把「谁忙、几人能到」摆给用户拍板，**不得自行改时间**。
  只有忙闲**接口调用失败**时才降级放行，并在台账里记 `skipped`。
- 第 3 步 `status` 不是 `bookable` → **停下**，把 `recommendations` 按「会议室名 + 楼层 + 容量」列出
  让用户选；哪怕只有一个候选也要确认，**禁止静默替换**。
- **会议室是第 4 步的前置阻塞项**：提到了会议室但 `meeting_room_id` 仍为空就**不建**。严禁「先把
  日程建起来、会议室回头补」——会议室名只写进 `location` **等于没订**。
- 第 4 步成功、第 5 步失败 → 明说「日程/会议已建好，参与人已收到系统邀请，但这条额外通知没发出去」，
  并把参与人名单给用户自行通知。**绝不因通知失败去取消日程**：取消会再推一次通知，链接还不可重建。

## Recipe 4 · 文档协作开场（新建 → 授权 → 通知）

**触发语**：「建个方案文档，把张三加进来一起写，再到群里说一声」「起一份周报模板发给团队」
**跨产品**：smartpage（或 doc）+ doc-manage + message
**性质**：含**权限扩散**与**对外发送**两类高风险，必须分两次确认

```bash
# 1 新建（没指明类型时默认智能文档；用户明说 Word 才走 wecomcli-doc）
wecom-cli smartpage create --json '{"name":"2026 Q4 项目方案"}'
#   已有初稿：smartpage import --json '{"file_path":"/abs/path/方案.md","name":"2026 Q4 项目方案"}'
# 2 姓名 → userid
wecom-cli contact users search --json '{"keywords":["张三"]}'
# 3 【单独确认】加协作成员
wecom-cli doc members update --docid '<docid>' \
  --add-member-list '{"items":[{"userid":"<userid>","user_type":"user","user_auth":"read"}]}'
# 4 【再单独确认】发通知，正文里给 [文档名](url)
wecom-cli message aibot sessions list
wecom-cli message aibot send --chat-id '<本次返回的 chat_id>' --msg-type markdown \
  --markdown '{"content":"《2026 Q4 项目方案》已建好，可直接查看：<url>"}'
```

**顺序上的硬约束**

- **先授权、后通知，顺序不可颠倒。** 反过来会让收件人点开一个自己打不开的链接。
- 第 3 步是权限扩散（被授权者立刻能看到**全部内容**），第 4 步是对外发送（不可撤回），**两次确认
  必须分开**，一句「好」不能吞掉两步。
- 权限档位不确定时**问一句，默认 `read` 不默认 `edit`**。「把他加进来」**不构成**授予编辑权的明确表示。
- `doc members update` **只能加人、不能删人**，CLI 没有移除成员的方法。加错了本技能删不掉，只能引导
  用户去客户端手动移除——所以宁可先问。

**中途失败的降级**

- 第 3 步失败 → **不发通知**，把 `[文档名](url)` 给用户，说明授权没成功。
- 第 3 步**部分成功** → 逐人列出结果，**通知只发给已授权成功的人**，其余单独告诉用户。
- 第 1 步成功但用户中途改主意 → 文档已经建出来了，如实说明并给出链接（CLI 没有删除文档的方法）。

## Recipe 5 · 逾期待办巡检并提醒

**触发语**：「有哪些待办超期了，提醒一下负责人」「催一下没做完的事」
**跨产品**：todo + message　**性质**：读 + **对外发通知**，本技能里风险最高的一条

```bash
# 1 进行中且截止时间已过的待办，翻页到 has_more=false
wecom-cli todo list --json '{"status_filter":["proceed"],
  "deadline_end_time":"2026-09-04 09:00:00","limit":20}' --page-count 10
# 2 本地按 deadline.value 与当前时刻比对筛逾期；没有 deadline 的不算逾期
# 3 分组到人：直接用 followers[].user_name（列表已带人名，不必再走 contact）
# 4 【完整列出「给谁 / 发什么 / 发到哪个会话」并取得同意】
# 5 发送——chat_id 必须取自本次刚调的 sessions list
wecom-cli message aibot sessions list
wecom-cli message aibot send --chat-id '<本次返回的 chat_id>' --msg-type markdown \
  --markdown '{"content":"提醒：待办「补充 Q4 预算测算」已于 9 月 3 日到期。"}'
```

**红线**

- **`chat_id` 必须来自本次刚调的 `sessions list`。** 用户在候选里选完后**再调一次**重新取值——
  会话按最后消息时间排序，这会儿顺序可能已经变了。历史上下文里的、用户给的、按名字拼的一律不可用。
- `sessions list` 最多 20 个会话且不分页。**目标不在里面就是发不了**：如实告知「对方不在机器人最近
  的会话范围内，需要对方先给机器人发一条消息」，**不得改用 `message send` 绕过**（实测 `853006`）。
- **逐个发、不群发**，每人内容单独列出确认；一次不超过 30 人。
- 巡检范围只覆盖机器人视角的待办（执行纪律第 6 条），汇报时说清楚。
- 提醒只读 + 发消息，**不要顺手把逾期待办标完成或删掉**——`todo finish` 无反向操作，`todo delete` 也无恢复接口。

## 定时与事件驱动

recipe 只描述**做什么**；**什么时候做**交给 DesireCore 的调度（如每天早上跑一次晨间简报）。

⚠️ **企业微信 CLI 没有任何事件订阅 / 长连接能力**（13 个服务里没有 event 服务）。
**禁止用 `while true` + `sleep` 轮询消息、邮件或待办来模拟「有新的就通知我」。** 用户要这类能力时
如实告知做不到，请他稍后自己来问，或由 DesireCore 侧定时跑只读 recipe。

## 已核实不成立的编排（不要设计成 recipe）

| 想做的事 | 为什么不成立 | 能做的替代 |
|---|---|---|
| 把在线文档/表格「归档进微盘」 | `disk files upload` 只吃**本地文件路径**或 `media_id`；CLI **没有**移动/复制方法；在线文档也**不能** `disk files download` | 只能「本地产物 → `disk files upload`」，或把 `doc_url` 汇总写进一份索引文档 |
| 读群聊消息后自动回复 / 值班机器人 | `chat groups list` 实测 `853006`，且无事件订阅能力 | 用户明确指定某个会话时由 `wecom-chat` 单独读；不做自动化 |
| 按已读状态或标签整理邮箱 | `mail` 只有 `get` / `search` / `send`，**没有**标记已读、打标签、删除、存草稿 | 只做「搜出来 + 汇总告诉用户」，写操作引导去客户端 |
| 生成并提交周报 / 日报 | 企业微信**没有**日志汇报这个产品（钉钉才有），CLI 里没有对应服务 | 汇总日程+会议+待办后落成一份文档，由用户自己发出去 |
| 周期日程 / 周期会议的批量编排 | `create` / `update` / `cancel` 对周期日程与周期会议**全不支持** | 告知不支持并引导到客户端；**禁止**用「建多条单次」变通 |

## 不做什么（指向具体技能）

| 用户想做的事 | 去哪儿 |
|---|---|
| 单独约日程 / 查安排 / 订会议室 / 查共同空闲 | `wecomcli-calendar` |
| 单独开在线会议 / 查会议 / 取纪要或转写原文 | `wecomcli-meeting` |
| 单独记、查、改、完成待办 | `wecomcli-todo` |
| 单独发一条消息或文件；单独发 / 回 / 转 / 搜邮件 | `wecomcli-message` / `wecomcli-email` |
| 搜文档、改文档名、加成员、改加入规则（任何文档类型） | `wecomcli-doc-manage` |
| 文档正文读写：智能文档 / 在线文档 / 在线表格 / 智能表格 | `wecomcli-smartpage` / `wecomcli-doc` / `wecomcli-sheet` / `wecomcli-smartsheet` |
| 微盘找文件、上传、下载、建文件夹；媒体文件拿 `media_id` | `wecomcli-disk` / `wecomcli-media` |
| 姓名 → userid、查部门职务邮箱；读某个会话的聊天记录 | `wecomcli-contact` / `wecom-chat` |
| CLI 安装 / 版本 / 授权 / 身份 / 全局铁律 | `wecom-shared` |
