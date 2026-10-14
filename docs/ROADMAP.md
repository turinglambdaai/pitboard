# 路线图（Roadmap）

以 AIHOT 为参照系的差距分析与实施计划。原则：**策略与实现可以借鉴，信息源必须自建**；
热度引擎保持确定性（无 LLM 也可运行），LLM 永远只做增强层。

## 对 AIHOT 的差距分析

### 已吸收（并有自己的形态）

| AIHOT 能力 | pitboard 形态 |
| --- | --- |
| 多信源 + 分级准入 | 17 feed + org 监控 + HN + arXiv，tier 1/2/3 ×1.35/1.0/0.85 |
| 判重 → 聚簇 → 独立来源数热度 | Jaccard 聚簇 + 独立来源数 × 时间衰减（纯函数、可测试、无 LLM 可跑）|
| 新/上升标记 | ✅ |
| 规则驱动编日报 | ✅ 每日 07:30 自动出刊 |
| Agent 出口（RSS/API/MD/llms.txt） | ✅ + 独有 SSE 出刊推送 |
| 主题页 | ✅ 话题雷达（关键词版）|
| 深浅色 | ✅ 零依赖 |
| 公开提示词/标准 | ✅ 热度词典与信源全部在 config 可配 |

### pitboard 有而 AIHOT 没有

- **确定性热度引擎**（AIHOT 每条内容两次 LLM 打分；我们规则打底、LLM 只做增强，
  成本为零、结果可复现、可测试——23 个测试锁定行为）
- **每源配额 + 开源雷达分栏**（单一 outlet 永远刷不了屏）
- **话题雷达**（跨归档话题追踪）
- **静态镜像部署**（GitHub Actions + Pages，零服务器；AIHOT 需要 PG + Docker 全家桶）
- **单进程自托管**（无数据库，备份即拷贝 data/）

### 尚未落地（本轮规划补齐）

见下方 M1/M2 里程碑。

## M1 — 内容与追踪（信息质量是产品生命线）

1. ✅ **跨日事件跟踪（跟进标记）**
   事件指纹（标题+实体归一化哈希）跨归档比对：今日事件若与历史事件同指纹，
   标「进展」并链接首见日期；卡片展示「首见 → 至今 N 天」。
   验收：同事件第二日报导自动带进展标记。
2. ✅ **周报 / 月报**
   从日报汇编（规则选 TOP，无 LLM 也可出刊）；`raco pitboard weekly` 生成，
   站点 /weekly/ 归档。
3. **网页列表源升级**
   web_list 支持「标题 + 日期」结构规则（逐站适配），目标站点：盖世汽车、
   42how、中汽研、工信部政策页；Vector 复测反爬。
4. **中文通道建设**
   自托管 RSSHub（fnOS NAS Docker）接 36kr 快讯/盖世等路由；公众号桥
   （wechat2rss 类）选型验证。目标：中文通俗层 ≥3 个稳定源。
5. ✅ **JSON 接口源**
   通用 JSON API 源类型（第一批：NHTSA 召回、GitHub Releases 聚合）。
6. ✅ **OG 分享图**
   出刊日自动生成 og:image（Racket 侧 SVG 转 PNG 或纯 SVG），分享到
   社交平台有卡片。

## M2 — 运营与工程（把自托管和 agent 体验做实）

1. ✅ **/admin 后台（只读状态页；试抓需 PITBOARD_ADMIN=1）**：信源试抓（单源 dry-run）、内容诊断（聚簇抽样审查）、
   运行状态（源健康/时长）；只读，无写操作。
2. ✅ **MCP 出口**（stdio JSON-RPC，`raco pitboard mcp`）：让 agent 直接查询今日/历史热点、按话题订阅。
3. ✅ **OpenAPI 规范**（/openapi.json）：openapi.json 描述全部只读 API。
4. ✅ **Dockerfile + compose 已入库；NAS 实机部署待做**：自托管默认路径；数据卷即 data/。
5. ✅ **LLM 预算熔断 + prompt 配置文件化**：单日出刊 LLM 调用上限、失败退避；
   提示词移入 config/prompts/（对齐 AIHOT 的 prompts 公开实践）。
6. ✅ **精选评测脚本**（raco pitboard eval）：自标注样本 + 出刊结果对比，量化「精选准确率」，
   调阈值不再靠感觉。
7. ✅ **运行告警**（health.json 连续失败 + webhook）：信源连续 N 期失败 → 状态页标红 + 可选 webhook 通知。
8. ✅ **站内全文搜索**（search-index.json + 客户端检索）：静态预建索引（分词倒排 JSON）+ 客户端检索，跨归档。

## M3 — 扩张

1. **信源类型补全**：✅ 自定义脚本推送（POST /ingest + token）；X 账号（自建桥）、
   公众号量产待基础设施。
2. **主题页实体化**：从关键词版升级为实体版（公司/方向/内容形态三类，
   AIHOT 形态）。
3. ✅ **收藏与稍后读**：卡片 ☆ 收藏 + /bookmarks.html 书签页 + JSON 导入导出。
4. **反哺 Racket 生态**：feed.rkt（RSS/Atom 解析）、sse.rkt（SSE hub）
   按库质量门禁独立发版上 catalog。
5. **移动端**：iOS/iPadOS/watchOS/Android 客户端（等 rivet 移动宿主就绪）。

## M4 — Agent 分层接入（设计预留）

三层架构，编辑侧与消费侧已就位或低成本预留，读者侧留决策不实现：

### L1 编辑侧 agent（站点自己的 AI 增强）— ✅ 通道已就位

`llm.rkt` 已是 OpenAI 兼容单端点（`PITBOARD_LLM_API_KEY/BASE_URL/MODEL`
三个 env），带预算熔断、失败降级 scored。**接入任何免费/便宜模型 =
设三个环境变量，零代码**。管线契约固定为 `(entries → i ⇒ title/summary)`，
未来从「单轮改写」升级为「多轮 agent（读原文、交叉验证、专题串联）」
只换 llm.rkt 内部，管线与降级不变式不动。

### L2 读者侧 BYOK（用户自带模型）— 📋 留决策不实现

设计定调（做的时候照此执行）：静态站 + **纯客户端 BYOK**——设置面板把
endpoint/key/model 存 localStorage，前端直接调 provider，服务器零接触，
静态托管兼容。已知约束：多数 provider 不开浏览器 CORS，届时引导
「支持 CORS 的 provider / 用户自建反代 / 自托管实例（服务端 LLM 管线
现成）」三条路。前置条件：产品化阶段；现在不做 UI，只在此记录设计。

### L3 消费侧（把 pitboard 变成用户 agent 的数据源）— ✅ 10-14 落地

- ✅ **Agent Skill**：`skill/pitboard/SKILL.md`，站点直出
  `/skill/pitboard/SKILL.md`，教 agent 用数据端点、JSON 结构、
  简报/话题追踪/跨日对比配方与引用约定（回源 url）。
- ✅ **llms.txt 完整化**：topics/openapi/search-index/skill/MCP 全收录。
- ✅ 基础件（M2 已建）：MCP 三工具、OpenAPI、REST+SSE。
- 📋 待做：skill 仓库化分发（单独 repo 或 skill marketplace）、
  公众号源接入后给 agent 的中文全文摘要通道。

## 执行约定

- 每个里程碑先落验收标准再动工；引擎行为变更必须带测试。
- 信息源变更走 docs/SOURCES.md 流程（实测 → 接入 → 观察 3 天 → 转正/摘除）。
- 对 AIHOT：只借鉴已验证的设计，不抄实现（技术栈不同），对外不引流。
