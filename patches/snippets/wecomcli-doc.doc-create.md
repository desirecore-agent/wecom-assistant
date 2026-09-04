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

