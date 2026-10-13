# Changelog

All notable changes to this project are documented in this file.

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
