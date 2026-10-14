# pitboard

[![CI](https://github.com/turinglambdaai/pitboard/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/pitboard/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

汽车行业的每日热点日报站：把开源项目、行业资讯、前沿论文抓到一起，聚簇去重，
按独立来源数与时间衰减算出热度，每天出刊一张「pit 板」。Racket 全栈
（web-server），单进程自托管，零外部依赖（无数据库）。

语言：Racket

## 它怎么工作

```
RSS 媒体源 ─┐
GitHub 话题 ─┼→ 抓取 → 归一化 → 聚簇(Jaccard/中英分词) → 热度(独立来源数×时间衰减) → 出刊
arXiv 论文 ─┘                                                        ↓
                                              站点 / RSS / JSON API / 日报.md / llms.txt / SSE
```

- **无 LLM 也可运行**：热度引擎是纯规则（聚簇 + 打分），所有信源免 key。
- **可选 LLM 增强**：配置任何 OpenAI 兼容接口后，头条热点自动改写为中文标题与摘要；
  失败或未配置时自动退回纯排序模式，站点功能不受影响。
- **Agent 友好**：`/rss.xml`、`/api/v1/latest.json`、`/daily/<date>.md`、
  `/llms.txt`、`/api/events`（SSE 出刊推送）全部开箱即用。

## 快速开始

需要 Racket 8.14+（含 minimal-racket；本机开发用的是 9.3）。

```sh
# 安装为 Racket 包（自动带上 web-server 与 http-easy 依赖）
raco pkg install --auto https://github.com/turinglambdaai/pitboard.git

# 出刊（抓取 + 聚簇 + 落盘 data/YYYY-MM-DD.json）
raco pitboard fetch --config config/sources.json

# 起站点（默认 8090 端口）
raco pitboard serve --port 8090

# 生成 GitHub Pages 静态镜像到 site/
raco pitboard export --out site
```

克隆开发用 `raco pkg install --auto --link .` 本地链接即可，测试跑 `raco test -p pitboard`。

## 配置

### 信源（`config/sources.json`）

| 字段 | 说明 |
| --- | --- |
| `feeds` | RSS 源列表，`name` / `url` / `weight`（权重参与热度） |
| `github.topics` | GitHub 话题搜索词（近 30 天有推送的仓库按 star 排序 + 近 90 天新星仓库） |
| `arxiv` | arXiv API 查询串与条数上限 |

默认配置即仓库内 `config/sources.json`：Ars Technica Cars、TechCrunch
Transportation、IEEE Spectrum Transportation、Electrek 四个媒体源 +
8 个汽车话题 + arXiv 机器人/系统工程论文。换成你自己的信源就是你的行业站。

### LLM（可选，环境变量）

| 变量 | 说明 |
| --- | --- |
| `PITBOARD_LLM_API_KEY` | OpenAI 兼容接口的 key（不设即纯排序模式） |
| `PITBOARD_LLM_BASE_URL` | 默认 `https://api.deepseek.com` |
| `PITBOARD_LLM_MODEL` | 默认 `deepseek-chat` |

`GITHUB_TOKEN` 存在时 GitHub 搜索走认证配额（Actions 中自动注入）。

## 自托管与部署

- **进程**：`raco pitboard serve` 一个进程全包（页面 + API + 静态资源 + SSE），
  数据就是 `data/*.json` 文件，备份即拷贝。
- **静态镜像**：仓库自带三个 GitHub Actions —— `ci.yml`（三平台测试）、
  `digest.yml`（每日 07:30 北京时间出刊并提交归档）、`pages.yml`（部署 site/ 到
  GitHub Pages）。Fork 后开启 Pages（构建方式选 "GitHub Actions"）即可得到
  同款日更站点。

## 目录结构

```
pitboard/            Racket 包主体（collection "pitboard"）
  cli.rkt            raco pitboard 入口（fetch / serve / export）
  sources.rkt        信源适配器（RSS / GitHub / arXiv）+ 硬超时
  feed.rkt           RSS 2.0 + Atom 解析（纯函数）
  score.rkt          分词、聚簇、热度、标签（新/上升）
  llm.rkt            OpenAI 兼容 LLM 增强（可选）
  store.rkt          data/YYYY-MM-DD.json 存储
  render.rkt         页面 / RSS / Markdown / llms.txt 渲染
  sse.rkt            SSE hub（出刊推送 + 心跳）
  app.rkt            web-server 应用
  export.rkt         GitHub Pages 静态导出
assets/              站点静态资源（零依赖 CSS/JS）
config/              信源配置
skill/pitboard/      agent 技能（权威源，站点 /skill/ 直出）
data/                每日刊物质档（Actions 每日提交）
site/                静态镜像（导出产物，Pages 部署源）
```

## 路线图

完整差距分析与里程碑见 [docs/ROADMAP.md](docs/ROADMAP.md)，要点：

- **M1 内容与追踪** — 跨日事件跟踪（进展标记）、周报/月报、网页列表源升级、
  中文通道建设（RSSHub 自托管 + 公众号桥）、JSON 接口源、OG 分享图。
- **M2 运营与工程** — /admin 信源后台、MCP 出口、OpenAPI、Docker（fnOS NAS）、
  LLM 预算熔断、精选评测脚本、运行告警、站内全文搜索。
- **M3+ 扩张** — X/公众号源量产、主题页实体化、收藏稍后读、feed/sse 抽包
  上 catalog、移动端（等 rivet 移动宿主）。
- **M4 Agent 分层** — 编辑侧 LLM 通道（免费模型 = 三个环境变量）、读者侧
  BYOK（留决策）、消费侧 agent skill + MCP + llms.txt。

## Agent 接入

pitboard 对 agent 是一等公民：站点出刊即发布机器可读的全套数据，
你的 agent 可以把它当汽车行业信息源直接用。

- **装技能**：把下面这句话发给你的 agent，剩下的它自己装：

  > 请安装 pitboard 技能：<https://pitboard.jrtx.site/skill/pitboard/SKILL.md>

  SKILL.md 自带 agent 自装指引；手动安装就是一条 curl（见该文件内的安装节）。
- **零安装用数据**：`/api/v1/latest.json`、`/api/v1/digest/<date>.json`、
  `/openapi.json`、`/llms.txt`，全部只读免鉴权。
- **自托管进阶**：`raco pitboard mcp` 提供 MCP 工具
  （latest_digest / get_edition / get_topic）；
  `PITBOARD_LLM_*` 环境变量接任何 OpenAI 兼容模型做出刊增强（可选，
  失败自动降级纯算法模式）。

## License

MIT
