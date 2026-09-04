
> ⚠️ **DesireCore 修正（2026-09-04）**：本文件的 `rooms search` 入参名已按 `wecom-cli 1.2.0`
> 的 `wecom-cli meeting rooms search --schema` 逐字段核对并修正。上游 commit
> `78c514b2afee7c0d3d7be715628478421f37ee63` 文档化的是 1.2.0 之前的旧参数名，
> 4 个过滤参数错了 3 个：`room_keyword` → `room_name`、`min_capacity` → `capacity_min`、
> `building_city` → `city_name`（`building_name` 与 `floor_name` 一直是对的，未改动）。
> **这是静默缺陷**：传旧名不会报错，后端直接忽略未知字段 → 会议室名 / 容量 / 城市过滤全部失效，
> 于是返回的是「该时段任意可订会议室」，Agent 会以为命中了用户指定的房间 → **订错房**。
> 修正由 `scripts/vendor-official-skills.sh` 按 `patches/param-renames.tsv` 自动重放，
> 上游修好同名问题后本条注记与替换表可一并撤除。
