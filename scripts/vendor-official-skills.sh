#!/usr/bin/env bash
#
# vendor-official-skills.sh —— 把企业微信官方 wecom-cli 的 Agent Skill vendor 进本仓库。
#
# 为什么要有这个脚本
# ------------------
# 本仓库 skills/ 下的 wecomcli-* 全部是 WecomTeam/wecom-cli（MIT）的**原样副本 + 一组必要补丁**。
# 目录名与技能 ID 一律保持 `wecomcli-` 前缀不变，一眼可辨来源。
# 补丁**全部是数据**（patches/*.tsv + patches/snippets/*.md），不是一次性手工编辑——
# 上游发新版时只需改 UPSTREAM_COMMIT 重跑本脚本，所有修改自动重放。
# **不要手工编辑 skills/wecomcli-*，改动会在下次重跑时被无声抹掉；请改 patches/ 下的数据。**
#
# 幂等性
# ------
# 每次运行都先删掉 skills/wecomcli-*，再从**干净的上游 checkout** 重新复制并重放补丁，
# 因此重复执行结果逐字节一致，不存在"补丁叠加"问题。
# 只删 `wecomcli-` 前缀的目录，skills/ 下我方自维护的技能（wecom-shared、wecom-workflows 等）不受影响。
#
# 为什么排除 wecomcli-shared
# --------------------------
# 官方 14 个技能里的 wecomcli-shared 是公共前置技能（CLI 安装/版本/授权检查 + 通用输出约束）。
# 我方自维护的 wecom-shared 承担同一职责，且是本 Agent 唯一的公共前置技能。两套并存会产生**互斥指令**：
#   - 版本门槛：官方写「不低于 1.1.0」，我方是 1.2.0（3 个会议室参数在 1.2.0 才改名，见补丁 3.2）
#   - 执行策略：官方要求「参数就绪后直接执行、无需确认」，与我方 write-high 操作的复述确认冲突
# 因此 wecomcli-shared 不 vendor，改由补丁 3.1 把 13 个技能里的引用统一改指到 wecom-shared。
#
# 用法
# ----
#   ./scripts/vendor-official-skills.sh                 # 用默认 pinned commit
#   ./scripts/vendor-official-skills.sh --commit <sha>  # bump 上游版本
#   ./scripts/vendor-official-skills.sh --keep-tmp      # 保留临时 checkout 便于比对
#
set -euo pipefail

UPSTREAM_REPO="https://github.com/WecomTeam/wecom-cli.git"
UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-78c514b2afee7c0d3d7be715628478421f37ee63}"
KEEP_TMP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --commit) UPSTREAM_COMMIT="${2:?--commit 需要一个 commit sha}"; shift 2 ;;
    --repo)   UPSTREAM_REPO="${2:?--repo 需要一个 git URL}"; shift 2 ;;
    --keep-tmp) KEEP_TMP=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
PATCH_DIR="$REPO_ROOT/patches"
SNIPPET_DIR="$PATCH_DIR/snippets"
THIRD_PARTY_DIR="$REPO_ROOT/third_party/wecom-cli"

# vendor 清单：官方 14 个技能减去 wecomcli-shared（理由见文件头）
VENDORED_SKILLS=(
  wecomcli-calendar
  wecomcli-contact
  wecomcli-disk
  wecomcli-doc
  wecomcli-doc-manage
  wecomcli-email
  wecomcli-media
  wecomcli-meeting
  wecomcli-message
  wecomcli-sheet
  wecomcli-smartpage
  wecomcli-smartsheet
  wecomcli-todo
)
EXCLUDED_SKILLS=( wecomcli-shared )

die() { echo "❌ $*" >&2; exit 1; }
note() { echo "  $*"; }

for f in skill-renames.tsv param-renames.tsv frontmatter.tsv injections.tsv; do
  [ -f "$PATCH_DIR/$f" ] || die "缺少补丁数据 patches/$f"
done

# ---------------------------------------------------------------- 工具函数

# 读 TSV：丢掉注释行与空行
read_tsv() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' || true; }

# 定长子串计数（不走正则，避免 Markdown 里的 []().* 被当模式）
# 注意：无匹配时 grep 退出码为 1，脚本开了 pipefail，必须 || true 吞掉，否则整脚本被 set -e 中断
count_fixed() { { grep -oF -- "$2" "$1" 2>/dev/null || true; } | wc -l | tr -d ' '; }

# 定长子串全量替换（不走 sed，避免分隔符与正则元字符问题）
replace_fixed() {
  local file=$1 old=$2 new=$3 tmp
  tmp="$(mktemp)"
  awk -v old="$old" -v new="$new" '
    {
      out=""; rest=$0
      while ((p = index(rest, old)) > 0) {
        out = out substr(rest, 1, p-1) new
        rest = substr(rest, p + length(old))
      }
      print out rest
    }' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# 把片段文件注入目标文件的锚点行前/后；锚点必须恰好命中 1 行，否则 fail closed
inject_snippet() {
  local target=$1 snippet=$2 position=$3 anchor=$4 hits tmp
  [ -f "$target" ]  || die "注入失败：目标文件不存在 $target"
  [ -f "$snippet" ] || die "注入失败：片段文件不存在 $snippet"
  hits="$(awk -v a="$anchor" 'index($0, a) > 0 { n++ } END { print n+0 }' "$target")"
  [ "$hits" = "1" ] || die "注入失败：锚点在 $(basename "$target") 中命中 $hits 行（要求恰好 1 行）
       锚点：$anchor
       上游结构可能已变，请核对后更新 patches/injections.tsv"
  tmp="$(mktemp)"
  awk -v a="$anchor" -v snip="$snippet" -v pos="$position" '
    function emit_snippet(   line) { while ((getline line < snip) > 0) print line; close(snip) }
    !done && index($0, a) > 0 {
      if (pos == "before") { emit_snippet(); print }
      else                 { print; emit_snippet() }
      done = 1; next
    }
    { print }
  ' "$target" > "$tmp"
  mv "$tmp" "$target"
}

# 给 SKILL.md 的 frontmatter 补齐缺失的根级字段（缺则补、有则不动）
patch_frontmatter() {
  local file=$1 version=$2 risk=$3 type=$4 status=$5
  local fm block tmp added=0
  # 取第一段 frontmatter（首个 --- 与第二个 --- 之间）
  fm="$(awk '/^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$file")"
  [ -n "$fm" ] || die "frontmatter 补齐失败：$file 没有可识别的 frontmatter"
  printf '%s\n' "$fm" | grep -q '^name:' || die "frontmatter 补齐失败：$file 的 frontmatter 缺 name:"

  block="$(mktemp)"
  # 只补根级（顶格）缺失的字段；上游若已声明则保留上游值
  printf '%s\n' "$fm" | grep -q '^version:'    || { echo "version: $version" >> "$block"; added=$((added+1)); }
  printf '%s\n' "$fm" | grep -q '^risk_level:' || { echo "risk_level: $risk" >> "$block"; added=$((added+1)); }
  printf '%s\n' "$fm" | grep -q '^type:'       || { echo "type: $type"       >> "$block"; added=$((added+1)); }
  printf '%s\n' "$fm" | grep -q '^status:'     || { echo "status: $status"   >> "$block"; added=$((added+1)); }

  if [ "$added" -gt 0 ]; then
    tmp="$(mktemp)"
    # 插在 name: 之后——name 恒为 frontmatter 首个根级键，位置确定且不会落进 metadata: 的缩进块
    awk -v blk="$block" '
      function emit(   line) { while ((getline line < blk) > 0) print line; close(blk) }
      !done && /^name:/ { print; emit(); done = 1; next }
      { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
  rm -f "$block"
  echo "$added"
}

# ---------------------------------------------------------------- 1. 拉取上游

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wecom-cli-vendor.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" = "1" ]; then echo "（--keep-tmp）临时 checkout 保留在：$TMP_DIR"
  else rm -rf "$TMP_DIR"; fi
}
trap cleanup EXIT

echo "==> 1/6 拉取上游 $UPSTREAM_REPO @ ${UPSTREAM_COMMIT:0:12}"
UPSTREAM="$TMP_DIR/wecom-cli"
git init -q "$UPSTREAM"
git -C "$UPSTREAM" remote add origin "$UPSTREAM_REPO"
# 精确 commit 的浅克隆；GitHub 偶发 SSL_ERROR_SYSCALL，重试 3 次
fetched=0
for attempt in 1 2 3; do
  if git -C "$UPSTREAM" fetch -q --depth 1 origin "$UPSTREAM_COMMIT" 2>/dev/null; then fetched=1; break; fi
  echo "    fetch 第 $attempt 次失败，重试…" >&2; sleep 3
done
[ "$fetched" = "1" ] || die "无法拉取 $UPSTREAM_REPO @ $UPSTREAM_COMMIT"
git -C "$UPSTREAM" checkout -q FETCH_HEAD
actual="$(git -C "$UPSTREAM" rev-parse HEAD)"
[ "$actual" = "$UPSTREAM_COMMIT" ] || die "checkout 的 commit 不是 pinned 值：$actual != $UPSTREAM_COMMIT"
note "checkout OK：$actual"

UP_SKILLS="$UPSTREAM/skills"
[ -d "$UP_SKILLS" ] || die "上游没有 skills/ 目录，结构可能已变"

# 校验：vendor 清单与排除清单在上游都存在（排除项消失说明上游重构了，得重新判断要不要排除）
for s in "${VENDORED_SKILLS[@]}"; do
  [ -f "$UP_SKILLS/$s/SKILL.md" ] || die "上游缺少技能 $s，请核对 VENDORED_SKILLS 清单"
done
for s in "${EXCLUDED_SKILLS[@]}"; do
  [ -d "$UP_SKILLS/$s" ] || die "上游已不存在被排除的 $s —— 排除理由可能失效，请人工复核后再重跑"
done
up_total="$(find "$UP_SKILLS" -maxdepth 1 -mindepth 1 -type d -name 'wecomcli-*' | wc -l | tr -d ' ')"
expected=$(( ${#VENDORED_SKILLS[@]} + ${#EXCLUDED_SKILLS[@]} ))
[ "$up_total" = "$expected" ] \
  || die "上游 wecomcli-* 技能数为 $up_total，与 vendor($((${#VENDORED_SKILLS[@]}))) + 排除($((${#EXCLUDED_SKILLS[@]}))) = $expected 不符。
       上游新增/删除了技能，请人工判断后更新脚本里的 VENDORED_SKILLS / EXCLUDED_SKILLS。"

# ---------------------------------------------------------------- 2. 复制

echo "==> 2/6 vendor ${#VENDORED_SKILLS[@]} 个技能到 skills/（排除：${EXCLUDED_SKILLS[*]}）"
mkdir -p "$SKILLS_DIR"
# 只清 wecomcli-* ——自维护技能（wecom-shared / wecom-workflows / …）绝不触碰
while IFS= read -r d; do
  case "$(basename "$d")" in
    wecomcli-*) rm -rf "$d" ;;
    *) die "内部错误：拒绝删除非 wecomcli- 前缀的目录 $d" ;;
  esac
done < <(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d -name 'wecomcli-*')

for s in "${VENDORED_SKILLS[@]}"; do
  cp -R "$UP_SKILLS/$s" "$SKILLS_DIR/$s"
done
note "已复制：${#VENDORED_SKILLS[@]} 个技能"

# MIT 署名义务：把 pinned commit 的上游 LICENSE 原样留在仓库里，NOTICE 指向它
mkdir -p "$THIRD_PARTY_DIR"
[ -f "$UPSTREAM/LICENSE" ] || die "上游 LICENSE 不存在，无法履行 MIT 署名义务"
cp "$UPSTREAM/LICENSE" "$THIRD_PARTY_DIR/LICENSE"
printf '%s\n' \
  "上游：$UPSTREAM_REPO" \
  "pinned commit：$UPSTREAM_COMMIT" \
  "本目录的 LICENSE 由 scripts/vendor-official-skills.sh 从该 commit 原样复制，请勿手工编辑。" \
  > "$THIRD_PARTY_DIR/README.md"
note "已固化上游 LICENSE → third_party/wecom-cli/LICENSE"

# 收集 vendor 后的文件清单，供后续补丁遍历
list_files() { find "${VENDOR_PATHS[@]}" -type f -name '*.md' | sort; }
VENDOR_PATHS=()
for s in "${VENDORED_SKILLS[@]}"; do VENDOR_PATHS+=( "$SKILLS_DIR/$s" ); done

# ---------------------------------------------------------------- 3. 补丁 3.1

echo "==> 3/6 补丁 3.1：公共前置技能引用改指 wecom-shared"
ref_changes=0
while IFS="$(printf '\t')" read -r old new; do
  [ -n "${old:-}" ] && [ -n "${new:-}" ] || continue
  while IFS= read -r f; do
    c="$(count_fixed "$f" "$old")"
    [ "$c" -gt 0 ] || continue
    replace_fixed "$f" "$old" "$new"
    ref_changes=$(( ref_changes + c ))
  done < <(list_files)
done < <(read_tsv "$PATCH_DIR/skill-renames.tsv")
note "改写引用：$ref_changes 处"

# ---------------------------------------------------------------- 4. 补丁 3.2

echo "==> 4/6 补丁 3.2：修正 meeting.rooms.search 入参名"
param_changes=0
while IFS="$(printf '\t')" read -r old new; do
  [ -n "${old:-}" ] && [ -n "${new:-}" ] || continue
  n=0
  while IFS= read -r f; do
    c="$(count_fixed "$f" "$old")"
    [ "$c" -gt 0 ] || continue
    replace_fixed "$f" "$old" "$new"
    n=$(( n + c ))
  done < <(list_files)
  [ "$n" -gt 0 ] && note "$old → $new：$n 处"
  param_changes=$(( param_changes + n ))
done < <(read_tsv "$PATCH_DIR/param-renames.tsv")
note "修正参数名：$param_changes 处"

# ---------------------------------------------------------------- 5. 补丁 3.2 注记 + 3.4 增补方法

echo "==> 5/6 补丁 3.2 注记 + 3.4：注入片段"
inject_count=0
while IFS="$(printf '\t')" read -r snippet target position anchor; do
  [ -n "${snippet:-}" ] && [ -n "${target:-}" ] || continue
  inject_snippet "$SKILLS_DIR/$target" "$SNIPPET_DIR/$snippet" "$position" "$anchor"
  note "$snippet → $target（$position 锚点）"
  inject_count=$(( inject_count + 1 ))
done < <(read_tsv "$PATCH_DIR/injections.tsv")
note "注入片段：$inject_count 个"

# ---------------------------------------------------------------- 6. 补丁 3.3

echo "==> 6/6 补丁 3.3：补齐 frontmatter 根级字段"
fm_skills=0 fm_fields=0
while IFS="$(printf '\t')" read -r skill version risk type status reason; do
  [ -n "${skill:-}" ] || continue
  f="$SKILLS_DIR/$skill/SKILL.md"
  [ -f "$f" ] || die "frontmatter 补齐失败：$skill 不在 vendor 清单里，请对齐 patches/frontmatter.tsv"
  added="$(patch_frontmatter "$f" "$version" "$risk" "$type" "$status")"
  [ "$added" -gt 0 ] && { fm_skills=$(( fm_skills + 1 )); fm_fields=$(( fm_fields + added )); }
  note "$(printf '%-22s risk_level=%-6s 补 %s 个字段' "$skill" "$risk" "$added")"
done < <(read_tsv "$PATCH_DIR/frontmatter.tsv")

# frontmatter.tsv 必须与 vendor 清单一一对应，避免漏配
fm_rows="$(read_tsv "$PATCH_DIR/frontmatter.tsv" | wc -l | tr -d ' ')"
[ "$fm_rows" = "${#VENDORED_SKILLS[@]}" ] \
  || die "patches/frontmatter.tsv 有 $fm_rows 行，与 vendor 的 ${#VENDORED_SKILLS[@]} 个技能不一致"

# ---------------------------------------------------------------- 验收（fail closed）

echo "==> 验收"
fail=0
# 旧写法必须从「上游正文」里彻底消失。唯一的例外是我方注入的片段——补丁 3.2 的注记
# 必须逐字列出旧参数名才能说清改了什么。因此允许量不写死，直接从 patches/snippets/ 现算：
# 注入后的残留数必须**恰好等于**我方片段自带的数量，多一处就说明有上游正文没被替换掉。
for tok in wecomcli-shared room_keyword min_capacity building_city; do
  allowed=0
  while IFS= read -r f; do
    allowed=$(( allowed + $(count_fixed "$f" "$tok") ))
  done < <(find "$SNIPPET_DIR" -type f -name '*.md' | sort)
  left=0
  while IFS= read -r f; do
    left=$(( left + $(count_fixed "$f" "$tok") ))
  done < <(list_files)
  if [ "$left" != "$allowed" ]; then
    echo "  ❌ $tok：上游正文残留 $(( left - allowed )) 处（我方片段内允许 $allowed 处）" >&2; fail=1
  elif [ "$allowed" -gt 0 ]; then
    note "✅ $tok：上游正文残留 0 处（我方注记内引用 $allowed 处，属预期）"
  else
    note "✅ $tok：残留 0 处"
  fi
done
# 每个技能的四个根级字段都必须齐了
for s in "${VENDORED_SKILLS[@]}"; do
  fm="$(awk '/^---[[:space:]]*$/{n++; next} n==1{print} n>=2{exit}' "$SKILLS_DIR/$s/SKILL.md")"
  for k in version risk_level type status; do
    printf '%s\n' "$fm" | grep -q "^$k:" || { echo "  ❌ $s 缺根级 $k" >&2; fail=1; }
  done
done
[ "$fail" = "0" ] || die "验收未通过"
note "✅ 13 个技能的 version / risk_level / type / status 均已就位"

# ---------------------------------------------------------------- 摘要

total_lines="$(find "${VENDOR_PATHS[@]}" -type f -exec cat {} + | wc -l | tr -d ' ')"
total_files="$(find "${VENDOR_PATHS[@]}" -type f | wc -l | tr -d ' ')"
cat <<SUMMARY

──────────────── vendor 摘要 ────────────────
上游仓库        $UPSTREAM_REPO
pinned commit   $UPSTREAM_COMMIT
vendor 技能     ${#VENDORED_SKILLS[@]} 个（$total_files 个文件 / $total_lines 行）
已排除          ${EXCLUDED_SKILLS[*]}（与自维护 wecom-shared 互斥，见脚本文件头）
补丁 3.1        改写公共技能引用 $ref_changes 处 → wecom-shared
补丁 3.2        修正 rooms search 入参名 $param_changes 处
补丁 3.2/3.4    注入片段 $inject_count 个（含 2 个 message 方法 + 1 个 doc 方法 + 参数修正注记）
补丁 3.3        为 $fm_skills 个技能补齐 $fm_fields 个 frontmatter 字段
─────────────────────────────────────────────
SUMMARY
