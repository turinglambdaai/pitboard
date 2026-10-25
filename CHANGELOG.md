# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- 搜索页索引加载失败不再静默（issue #1 交互审查验收项）：`/search-index.json`
  加载中、失败（HTTP 非 2xx 或非法 JSON）、无匹配三态各有可见文案，失败附显式
  「重试」按钮可恢复。状态文案是页面里的静态 `data-i18n` 元素，中英切换覆盖
  全部状态；结果行改用 DOM API 构建——外部信源标题不再经过 `innerHTML`。
  render-test 增加页面模板与 app.js 资产的双守卫断言（HTTP 检查、catch 分支、
  重试接线、中英失败/无匹配文案必须不同）。
- 修复书签页/搜索页导航脱节：两页从手写 `site-tpl/` 静态拷贝收敛为
  走 `page-shell` 的常规渲染函数（缺书签入口/语言切换/主题按钮/app.js
  的漂移 bug），页面 JS 迁为 `assets/app.js` 的特性 IIFE，
  `site-tpl/` 目录删除；render-test 加防漂移断言 + 泄漏扫描覆盖。
  搜索框顺带接入既有 `search.placeholder` 的英文切换。
- 新信源「发现报告」（fxbaogao.com）券商研报：`json_api` 通道接入
  匿名 SEO 端点（申万交运设备 + 电动化门控的电气设备），tier 2；
  通道本身补齐与 rss/web_list 的能力对齐——`url_template`（无 url
  字段条目的详情链接拼装）、`only/except_keywords` 门控、中文斜杠
  日期解析（`2026/10/13`）。首次被真实配置触发暴露并修复三个 M1
  潜伏 bug（path 解析 hash-ref 多参、date_field 键未符号化、#f 条目
  泄漏）；新增 sources-test（7 例，纯函数无网络）。
- 反哺抽包：`pitboard/sse.rkt` 与 `pitboard/feed.rkt` 抽成独立包
  [turinglambdaai/server-sent-events](https://github.com/turinglambdaai/server-sent-events) 与
  [turinglambdaai/feed](https://github.com/turinglambdaai/feed)。
  SSE hub 修复了每次通知客户端收到重复帧的问题（旧实现直写与信号量
  唤醒双路径）；feed 解析器通用化（不再内置 item 组装/清洗策略），
  URL 清洗、HTML 剥离与无链接条目过滤留在 `feed->items` 产品策略层。

## 0.1.0 — 2026-10-13

M0 首发：

- 三类信源：RSS（Ars Technica Cars / TechCrunch Transportation / IEEE Spectrum
  Transportation / Electrek）、GitHub 汽车话题仓库搜索、arXiv 论文检索。
- 无 LLM 也可运行的热度引擎：标题/摘要分词聚簇（中英双语，CJK 二元语法）、
  按独立来源数与时间衰减计算热度，标注「新」「上升」。
- 可选 LLM 增强：任何 OpenAI 兼容接口，将头条热点翻译为中文标题与摘要；
  未配置 key 时自动退化为纯排序模式。
- Racket web-server 全栈站点：今日榜、日期归档、关于页、RSS 输出、
  JSON API、Agent Markdown 日报、llms.txt、SSE 出刊推送（`/api/events`）。
- 静态导出器：`raco pitboard export` 生成 GitHub Pages 镜像站点。
- CLI：`raco pitboard fetch|serve|export`。
- GitHub Actions：三平台 CI、每日出刊流水线、Pages 部署。
