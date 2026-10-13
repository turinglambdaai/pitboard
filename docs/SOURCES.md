# 信源地图（Source Map）

pitboard 的信源资产。按「读者画像 → 信息产地 → 获取通道」三层维护。
**维护规则**：每个源必须逐个 `curl` 实测后才可接入（状态只认实测不认印象）；
每季度复核一次，死链摘除；封锁源记录封锁方式，避免重复踩坑。

- 读者画像：汽车 E/E 工程师——AUTOSAR、智能驾驶、车规 MCU/SoC、
  功能安全/信息安全、车载网络（CAN/以太网）、中央计算/域控。
- 通道类型：`rss`（含 Atom）、`web_list`（网页列表抓取）、`org-watch`
  （GitHub 组织监控）、`api`、`topic-tag`（聚合平台标签页）。
- 热度分级：tier 1 官方一手 ×1.35 / tier 2 专业媒体 ×1.0 / tier 3 综合媒体 ×0.85。

## 一、官方一手（tier 1）

| 源 | 通道 | 状态 |
| --- | --- | --- |
| AUTOSAR 官网新闻 | web_list（/news-events/detail/） | ✅ 已接入 |
| NVIDIA 开发者博客 | rss + 汽车关键词门控 | ✅ 已接入 |
| Zephyr 项目博客 | rss | ✅ 已接入 |
| GitHub: AUTOSAR / COVESA org | org-watch（无 star 门槛） | ✅ 已接入 |
| GitHub: eclipse-iceoryx / eclipse-kuksa 等 SDV org | org-watch | 📋 可扩展（每个 org 一条查询，注意速率） |
| Vector 官网（新闻/技术文库） | 网页抓取 | 🚫 406 反爬；内容靠专业媒体转述覆盖，M1 复测 |
| 厂商 newsroom（Infineon/NXP/ST/Renesas/TI） | — | 🚫 全部无 RSS（ST 567、其余 404）；新品发布由专业媒体覆盖 |
| SOAFEE | rss | 🚫 403 |

## 二、专业媒体（tier 2，已接入）

| 源 | 区域 | 备注 |
| --- | --- | --- |
| IEEE Spectrum · Transportation | EN | 工程质量最高的公开媒体 |
| EE Times | EN | 半导体/芯片，关键词门控（automotive/chip/mcu/soc/...） |
| The Verge · Transportation | EN | 智驾/EV 行业报道，可读性强 |
| Automotive Dive | EN | 行业新闻（Industry Dive 体系） |
| Just Auto | EN | OEM/供应链动态 |
| dev.to · Automotive | EN | 工程师文章 |
| Medium · AUTOSAR / Automotive Software / Automotive Cybersecurity | EN | 标签即门控；信息安全专题源 |
| 雷峰网 | CN | 唯一稳定的中文源，进排噪双向关键词门控 |
| NVIDIA/GitHub 之外的开发者内容 | — | arXiv（论文，cat:cs.RO/eess.SY/cs.AR + 汽车关键词）|

## 三、综合媒体（tier 3，已接入）

Ars Technica Cars、TechCrunch Transportation、Electrek、CleanTechnica、
Hacker News（Algolia 拉近 7 天全量 + 本地标题关键词过滤，词表见 sources.rkt）。

## 四、封锁与死亡名单（勿重复踩坑）

| 源 | 状态 |
| --- | --- |
| Automotive News / Automotive World / TU-Automotive / ADAS&AVI / Electrive / GreenCarReports | 403（Cloudflare） |
| Electronics Weekly | 403 |
| Vector / SOAFEE / SAE | 406/403 |
| 36kr feed | 返回 JS 壳网页（非 XML） |
| 虎嗅 / pingwest / 品玩 | 无 RSS 或超时 |
| 盖世汽车 / 第一电动 / 42how | 无 RSS（官网反爬或 404） |
| NHTSA API | 可用但美召回，中文读者价值低，暂缓 |
| Reddit RSS / rsshub.app 公网实例 | 超时（rsshub 需自托管，见下） |
| Hacker News Algolia query 通道 | ⚠️ 不可用于精确监控：typo 容忍 + 无 OR；只允许全量拉取后本地过滤 |

## 五、中文层策略（当前最大缺口）

中文汽车科技媒体（盖世、车东西/智东西、42号车库、建约车评、电动星球、
汽车之心）几乎全部栖息在微信公众号，无 RSS。三条路：

1. **自托管 RSSHub**（M2，fnOS NAS Docker）——36kr 快讯、盖世、部分公众号
   的路由现成，公网实例不可用但自托管稳定；
2. **网页列表源扩展**（M1）——把 web_list 类型升级为支持页面内标题+日期
   结构规则，逐站适配盖世/42how/中汽研/工信部政策页；
3. **公众号专项**（M1+）——微信文章抓取通道（wechat2rss 类自建桥），
   这是中文层真正的主战场。

## 六、话题雷达

日报只覆盖「今天」，话题的历史轨迹由话题页承载。watch_topics 配置于
`config/sources.json`（当前：AUTOSAR、DDS、SOME/IP、SOA、信息安全、
功能安全、安全刷写、UDS、车载以太网、域控、智能驾驶、Robotaxi、芯片），
页面在 `/topics/`，跨归档聚合。

## 七、调参事实

- 权重平衡点：news 底数 ×4.0、github 对数因子 1.5/cap 6、新闻与高星仓
  可竞争版面；主榜每源 ≤2 席（论文 ≤6）、速览榜每源 ≤1 席且 repo ≤3。
- 热词表两级权重（工程核心词 0.5–1.2 / 通用词 0.2–0.4），聚簇热度取
  单簇最强词分 ×0.12 加成。
- 任何源接入前：`curl` 实测 200 + XML 头 + 条目量；接入后观察 3 天，
  噪音率 >20% 的必须加门控或摘除。
