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
data/                每日刊物质档（Actions 每日提交）
site/                静态镜像（导出产物，Pages 部署源）
```

## 路线图

- **M1** — 更多信源种类（网页列表源、X 账号、微信公众号源、NHTSA 召回 API）、
  事件时间线页、周报/月报、站点 i18n。
- **M2** — MCP 出口（让 agent 直接订阅热点）、信源管理后台与试抓诊断、Docker 镜像。
- **M3+** — iOS / iPadOS / watchOS / Android 客户端（等 rivet 移动宿主就绪）；
  把 `feed.rkt`（RSS/Atom 解析）与 `sse.rkt`（SSE hub）抽成独立 Racket 包回馈社区
  （catalog 现无等价物）。

## License

MIT
