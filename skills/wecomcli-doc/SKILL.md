---
name: wecomcli-doc
version: 1.2.0
risk_level: high
type: procedural
status: enabled
description: 企微 doc 内容操作技能，包含新建在线文档、导入、读取、追加、覆盖写入等功能。仅当用户明确指定 'doc'、'docx'、'word'、'在线文档'、'office文档'，或提供 https://doc.weixin.qq.com/doc/xxx 链接时触发。本技能不处理未指明类型的“文档”请求；凡是“创建文档 / 写文档 / 整理成文档 / 输出到文档”等泛化表达，默认都必须路由到 wecomcli-smartpage（智能文档），本技能不得抢占。若请求包含字段、记录、筛选、排序、统计、分组等结构化数据语义，严禁用 doc + markdown 静态表格变通替代，应考虑使用智能文档或者智能表格。公共管理操作请使用 wecomcli-doc-manage；在线表格操作请使用 wecomcli-sheet；智能表格操作请使用 wecomcli-smartsheet。
metadata:
  requires:
    bins: ["wecom-cli"]
---

# 企业微信doc文档管理

> 执行任何 `wecom-cli` 命令前，必须先读取并完成 `wecom-shared` 技能的公共前置检查。

资源型 skill，负责doc文档（`doc`）的新建、导入与内容读写。

## 适用范围

### 适用

- 新建 / 导入企微 doc 文档
- 读取 doc 文档内容
- 向 doc 文档追加一行 / 覆盖写入doc 文档

### 不适用

- 搜索文档 / 修改文档权限 / 重命名 / 加成员 → 改用 `wecomcli-doc-manage`

### 易混淆场景路由

- 用户说"创建文档 / 写文档 / 整理成文档" 且未指定 doc 类型 → 改用 `wecomcli-smartpage`（智能文档为默认）
- 用户给的链接是 `https://doc.weixin.qq.com/smartpage/...` 或者 `https://page.weixin.qq.com/smartpage/...` → 改用 `wecomcli-smartpage`
- 若遇到的 `docid` 以 `a1` 或者 `b1` 开头（形如 `a1_xxxx`, `b1_xxxx`）→ 改用 `wecomcli-smartpage`

## 接口路由表

路由表第二列若是 `references/xxx.md` 链接 → 必须先用 `read` 工具读完该文件，再构造命令。

| 用户意图 | 参考位置                                                          |
|---|---------------------------------------------------------------|
| 新建doc文档（在线） | 见下方「新建doc文档」                                                  |
| 导入本地文件为企微doc文档 | 见下方「导入doc文档」                                                  |
| 读取doc文档内容 | 见下方「读取doc文档内容」                                                |
| 追加文本到doc文档末尾 | [+contents-append](references/doc-contents-append.md)       |
| 全量覆盖doc文档内容 | [+contents-overwrite](references/doc-contents-overwrite.md) |
| 直接新建 doc（空文档 / 纯文本 / markdown 初始内容） | 见下方「新建 doc — `doc create`（DesireCore 增补）」 |

### 写入语义裁定（追加 vs 覆盖）

- 默认追加：用户用「写入 / 写到 / 记录 / 补充 / 加进去 / 记一下」等中性动词，且未明确要求清空或替换时，一律走 `append`（追加，不破坏原有内容）。
- 仅显式覆盖：仅当用户明确出现「覆盖 / 重写 / 替换 / 清空重写 / 整个换成」等强语义词时，才走 `overwrite`。

## 接口详述

### 新建doc文档

新建企微doc文档统一走「**生成 `.docx` → 导入**」两步流程：

1. 生成 `.docx` 文件：按 [+doc-create](references/doc-create.md) 生成 `.docx` 文件。
2. 导入为企微doc文档：使用下方「导入doc文档」接口将生成的 `.docx` 文件导入为企微doc文档。注意import导入的时候 `file_name` 应和文档标题保持一致。

### 导入doc文档

把本地文件（`.doc` / `.docx` / `.txt`）导入为企微doc文档。

**命令**

```bash
wecom-cli doc import --json '<JSON 参数>'
```

**参数**

| 字段          | 类型 | 必填 | 默认值 | 语义 |
|-------------|---|---|---|---|
| `doc_type`  | string | 是 | `doc` | 固定为 `doc`（doc文档） |
| `file_name` | string | 是 | — | 二进制文件名（含后缀），用于业务判断源文件类型 |
| `file_path` | string | 是 | — | 源文件的本地绝对路径 |
| `passwd`    | string | 否 | — | Office 文件加密密码（若有） |

**返回**

| 字段 | 类型 | 说明 |
|---|---|---|
| `docid` | string | 导入完成后的文档 ID |
| `url` | string | 导入完成后的访问链接 |
| `task_status` | string | 任务状态枚举，如 `succ` 成功 |

### 读取doc文档内容

读取**doc文档**的文档内容。

**命令**

```bash
wecom-cli doc contents get --json '<JSON 参数>'
```

**参数**

| 字段 | 类型 | 必填 | 默认值 | 语义                                      |
|---|---|----|---|-----------------------------------------|
| `docid` | string | 是  | — | doc文档 ID                                |
| `content_type` | string | 否  | `markdown` | 返回内容格式枚举：`text` / `markdown` / `ooxml`； |

**返回**

| 字段 | 类型 | 说明 |
|---|---|---|
| `url` | string | 文档访问链接 |
| `name` | string | 文档名称 |
| `content` | string | 文档内容较短时直接返回的原文 |
| `file_path` | string | 文档内容较长时自动落盘的**本地文件路径**；需用 Read 工具读取路径内文本后再展示 |
| `document` | object | `content_type=ooxml` 时返回的文档对象 |
| `version` | int | 文档版本号 |

## 新建 doc — `doc create`（DesireCore 增补）

> 本节是 DesireCore 对上游 `wecomcli-doc` 的增补：上游 14 个技能全文没有一次用到
> `doc.create`，本节参数已按 `wecom-cli 1.2.0` 的 `wecom-cli doc create --schema`
> 逐字段核对。风险等级：**write-low**（新建独立文档，不覆盖任何既有内容）。

### 什么时候用它，什么时候不用

**主流程仍是上面的「生成 `.docx` → `doc import`」两步，不要改。** 理由：

1. `doc.create` 的初始内容通道只接受 `content_type` ∈ `text` / `markdown`，本质是灌一段纯文本
   或 markdown。而用户说「生成一份 word 文档」时通常期待**封面标题、多级标题、列表、表格、
   局部加粗与配色**——这些只有走 `.docx` 导入才能一次性带进去。
2. 两步流程与 `wecomcli-sheet` / `wecomcli-smartpage` 形态一致（本地产物 → import），
   Agent 只需掌握一套心智模型。
3. `doc.create` 另有 `doc_requests`（document 节点编辑写入）这条结构化通道，但
   `OaUpdateRequest` 的节点结构在 schema 里**没有可直接照抄的书写规范**，且上游零使用，
   现场发明极易失败 —— **不要用 `doc_requests`**。

**只在下面这一类场景用 `doc create`**：用户要的就是**空文档**，或**只有几行纯文字 / 简单
markdown、明确不需要排版**的文档。这时一条命令就能完成，比「写 JSONL → 跑 python → import」
轻得多。判断不准就走主流程，不要临场切换。

> `doc.create` 与 `sheet.create` 在后端是**同一个方法的两个别名**（请求体都是 `OaDocCreateReq`，
> 靠 `doc_type` 区分）。要建在线表格请直接用 `wecomcli-sheet`，不要在本技能里传 `doc_type=sheet`。

### 命令

```bash
# 空文档
wecom-cli doc create --doc-name '项目周报'

# 带纯文本初始内容（单行）
wecom-cli doc create \
  --doc-name '会议纪要' \
  --content-type text \
  --content '2026-09-04 项目对齐会：下周一交付初版。'

# 内容里要带换行时，用 $'...' 让 shell 真的展开转义；
# 直接写 --content '第一行\n第二行' 传过去的是字面量反斜杠 n，不是换行
wecom-cli doc create \
  --doc-name '会议纪要' \
  --content-type text \
  --content $'2026-09-04 项目对齐会\n结论：下周一交付初版。'

# 带 markdown 初始内容
wecom-cli doc create --json '{
  "doc_name": "会议纪要",
  "doc_type": "doc",
  "content_type": "markdown",
  "content": "# 会议纪要\n\n- 结论：下周一交付初版。"
}'
```

### 参数

| 字段 | 类型 | 必填 | 默认 | 说明 |
|---|---|:---:|---|---|
| `doc_name` | string | **是** | — | 文档标题，长度 1–255。**唯一必填字段** |
| `doc_type` | string | 否 | `doc` | enum `doc` / `sheet` / `smartsheet`；本技能只用 `doc` |
| `content` | string | 否 | — | 纯文本初始内容，仅 `doc_type=doc` 有效，上限 1048576 字符；与 `file_path` 二选一 |
| `content_type` | string | 否 | `text` | enum `text` / `markdown`，仅 `doc_type=doc` 有效 |
| `file_path` | string | 否 | — | 从本地文件读初始内容，与 `content` 二选一 |
| `doc_requests` | array | 否 | — | 结构化节点写入，与 `content` 二选一 —— **见上，不要用** |

> `fields` / `sheet_title` / `grid_data` 只在 `doc_type=smartsheet` / `sheet` 时有效，本技能不涉及。

### 返回

| 字段 | 类型 | 说明 |
|---|---|---|
| `docid` | string | 新建文档 ID —— **内部流转，禁止展示给用户** |
| `doc_name` | string | 文档名 |
| `url` | string | 文档访问链接 |

建成后按本技能的 `docid` 使用规则，用 `[doc_name](url)` 回给用户。

## 跨技能依赖

| 依赖技能 | 何时触发 | 使用被依赖 skill 做什么                                                                                                             |
|---|---|-----------------------------------------------------------------------------------------------------------------------------|
| `wecomcli-doc-manage` | 用户只给文档名称/关键词，需先拿 `docid` 再读写内容 | 使用 `wecomcli-doc-manage` skill 搜索文档拿 `docid`                                                                                   |
| `wecomcli-smartpage` | 读取doc文档内容后，用户要求"做成智能文档/排版成 smartpage" | 使用 `wecomcli-smartpage` skill 生成智能文档                                                                                           |

> 参数缺失 / `docid` 搜索多候选等歧义场景，用简洁自然语言仅追问缺失或有歧义的信息；有候选项时在文字中列出供用户选择，不得自行猜测。

## `docid` 使用规则

`docid`仅cli使用。
最终展示用户时，不应展示 `docid`，而是使用文档 URL：

```
[doc_name](doc_url)
```


`docid` 是文档的唯一标识符，调用任何文档内容操作技能时均需提供。禁止自造 `docid`，按以下优先级获取：

1. 从文档链接提取（优先）：用户提供了企微文档 URL 时，直接从 URL 中解析。URL 格式为 `https://doc.weixin.qq.com/<type>/<docid>?scode=...`，取 `/<type>/` 后、`?` 前的部分即为 docid。
2. 通过文档搜索获取（备选）：用户仅提供文档名称或关键词、未给链接时，先调用 `wecomcli-doc-manage` 搜索文档，从返回结果中取 `docid`。
3. 用户直接提供：用户明确给出了完整 `docid`，可直接使用，无需再提取或搜索。
