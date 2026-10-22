# AGENTS.md

pitboard——汽车行业每日热点日报站（Racket 全栈 web-server，单进程自托管、零数据库），热度引擎 = CJK 二元语法 + Jaccard 聚簇 + 独立来源数×时间衰减。

## 结构

- `pitboard/` — 单 Racket 包全部模块：`app.rkt`（servlet）/ `cli.rkt` / `fetch` 管线（`sources.rkt` 信源、`score.rkt` 热度、`store.rkt` 存储）/ `render.rkt` + `export.rkt`（静态站写出）/ `llm.rkt`（可选 LLM）/ `mcp.rkt`；`tests/` 在包内
- `config/` — `sources.json` 信源配置（每源配额/分级/正则都在这里）
- `site/` — 导出的静态站产物；`data/` — 每日数据（不手改）；`skill/pitboard/` — agent SKILL.md 镜像（权威在 pitboard-skill 仓库，CI 防漂移）；`assets/`、`docs/`

## 常用命令

```bash
# CI 同款
raco pkg install --auto --no-docs http-easy server-sent-events feed
raco pkg install --auto --no-docs --link "$(pwd)"
raco test -p pitboard
raco make pitboard/app.rkt

# 本地出刊（digest.yml 同款）
raco pitboard fetch --data data --config config/sources.json
raco pitboard export --data data --out site --domain pitboard.jrtx.site
```

## 验证与发版

- CI（`ci.yml`）：装依赖 + `raco test -p pitboard` + `raco make`。
- `digest.yml`（定时）：fetch → export → 部署，线上 pitboard.jrtx.site。
- `pages.yml`：站点部署。workflow 模式下 CNAME 必须显式 PUT，部署失败先查这条。
- 发版 = GitHub tag（MIT，0.1.0 已发）；站点数据问题以 `data/` 与 workflow 日志为准。

## 仓库特定规矩

- 泄漏/序列化类防线 = 输出侧扫描（对 `site/` 产物正则扫描），不是只测源码；新增出口（模板/sitemap/feed）必须进产物门禁。
- 配置正则一律 `pregexp`（Racket 9.3 `#rx` 方言无 `\w`/`{n}`，踩过雷）。
- `skill/pitboard/` 是镜像勿直改，权威在 turinglambdaai/pitboard-skill，CI 守卫一致性。
- jsexpr 不收 symbol、`xexpr` 数字 0 非法等 Racket 序列化坑已踩过一轮，改 render/export 前先看 tests。

## 组合定位（Portfolio placement）

- 轨道与授权：轨道 4 社区引流；授权形态：MIT；商业归属：永久免费（汽车内容资产）。
- 组合归属唯一权威：[PORTFOLIO.md](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md)（turinglambdaai.github.io 仓库）。改归属/授权先改权威档，再同步本节。
- 纪律：价格只进本仓 `PRICING.md`，且收费开始时才发布；README 与产品站不做价格预告。
