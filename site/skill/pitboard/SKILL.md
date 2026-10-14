---
name: pitboard
description: 查询 pitboard（汽车行业每日热点日报）的行业热点、话题跨期追踪与历史归档。当用户要汽车行业新闻简报、智能驾驶/开源项目/芯片/政策动态，或要把当日热点汇总进自己的工作流时使用。
---

# pitboard — 汽车行业每日热点

pitboard（https://pitboard.jrtx.site）是每日自动出刊的汽车行业热点日报：
23 个信源（AUTOSAR 官方、GitHub、arXiv、Hacker News、盖世汽车、新出行、
第一电动、雷峰网……）抓取 → 中英分词聚簇去重 → 按独立来源数 × 时间衰减
算热度。北京时间约 07:30 出刊，全年无休。

## 数据端点（全部只读、无需鉴权、静态直出）

| 端点 | 用途 |
| --- | --- |
| `GET /api/v1/latest.json` | 最新一期完整 JSON |
| `GET /api/v1/digest/<YYYY-MM-DD>.json` | 指定日期 JSON（建站以来每日归档） |
| `GET /openapi.json` | 全部只读 API 的 OpenAPI 规范 |
| `GET /daily/<date>.md` | Markdown 版日报 |
| `GET /search-index.json` | 全站标题检索索引（客户端检索用） |
| `GET /topics/` | 话题雷达（24 个 E/E 话题跨期追踪） |
| `GET /api/events` | SSE 出刊推送（仅自托管 serve 模式） |

域名以 `https://pitboard.jrtx.site` 为准；自托管实例换自己的域名。

## JSON 结构

```
digest = {date, generated_at, mode, clusters[], sources[]}
cluster = {id, title, heat, labels[], items[]}
item    = {id, kind, source, source_url, title, summary, url,
           published_at, extra{weight, ...}}
```

- `kind`：`news`（资讯）/ `github`（开源仓库）/ `paper`（论文）。
- `url` 指向原文；**引用必须回源**，pitboard 只是聚簇摘要。
- `heat` 是同版内相对值，跨版不可比。
- `labels`：`new` 首见 / `progress` 跨期进展（同一事件连续多日出现）/
  `rising` 升温。
- `mode`：`scored`（纯算法）或 `llm`（头条经 LLM 中文改写）。

## 典型任务

### 每日简报
1. `GET /api/v1/latest.json`，取 `clusters` 前 10。
2. 每簇输出一行：`heat + title + 首条 item 的 url`。
3. 有 `progress` 标注的注明「进展」。

### 话题追踪
1. `GET /topics/` 拿话题清单（方向 / 公司 / 形态三组，如 AUTOSAR、
   SOME/IP、UDS、智能驾驶、Robotaxi、比亚迪、华为车、召回、政策）。
2. 单话题历史：逐日 `digest/<date>.json` 过滤簇标题包含该词；或
   自托管后走 MCP `get_topic`（一步到位）。

### 跨日对比
取两个日期的 digest，对簇标题做相似度归并（小写 + 去标点 + 前缀匹配
即可），报告「新出现 / 持续 / 消失」三类事件。

## MCP（自托管）

`raco pitboard mcp` 启动 stdio MCP server，工具：
`latest_digest` / `get_edition(date)` / `get_topic(term)`。
agent 配置示例（claude）：

```json
{ "mcpServers": { "pitboard": { "command": "raco",
    "args": ["pitboard", "mcp"], "cwd": "<pitboard 仓库>" } } }
```

## 安装

**推荐：把链接发给你的 agent**，剩下的它自己搞定——复制这句话给任何支持技能的 agent：

> 请安装 pitboard 技能：<https://pitboard.jrtx.site/skill/pitboard/SKILL.md>

**如果你就是那个 agent**：获取上面的 SKILL.md，原样保存到你的技能目录
`pitboard/SKILL.md` —— Claude Code 是 `~/.claude/skills/pitboard/SKILL.md`，
ZCode 是 `~/.zcode/skills/pitboard/SKILL.md`，其他 agent 按各自的技能目录约定
放置，然后按你的机制重新加载技能。技能零依赖，只读公开 JSON API。

**手动安装**（不用 agent 时）：

    mkdir -p ~/.claude/skills/pitboard
    curl -fsSL https://pitboard.jrtx.site/skill/pitboard/SKILL.md \
      -o ~/.claude/skills/pitboard/SKILL.md

本技能的权威来源是 pitboard 主仓库 `skill/pitboard/SKILL.md`，站点
`/skill/pitboard/SKILL.md` 为其每日同步的直出副本。

## 约定

- 引用回源：给用户的每条新闻附 `url` 字段原文链接，pitboard 页面
  仅作补充。
- 出刊前（北京 07:30 前）查询昨日 digest；自托管可订阅 `/api/events`
  的 SSE 等出刊事件。
- pitboard 的摘要是聚合产物，重要决策请读原文。
