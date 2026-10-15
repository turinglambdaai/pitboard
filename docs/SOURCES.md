# 信源地图（Source Map）

pitboard 的信源资产。按「读者画像 → 信息产地 → 获取通道」三层维护。
**维护规则**：每个源必须逐个 `curl` 实测后才可接入（状态只认实测不认印象）；
每季度复核一次，死链摘除；封锁源记录封锁方式，避免重复踩坑。

- 读者画像：汽车 E/E 工程师——AUTOSAR、智能驾驶、车规 MCU/SoC、
  功能安全/信息安全、车载网络（CAN/以太网）、中央计算/域控。
- 通道类型：`rss`（含 Atom）、`web_list`（网页列表抓取）、`org-watch`
  （GitHub 组织监控）、`api`（公开 JSON API，见「八、公开 JSON API 通道」）、
  `topic-tag`（聚合平台标签页）。
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
| 雷峰网 | CN | 进排噪双向关键词门控 |
| 盖世汽车 | CN | 行业综合旗舰，web_list（列表页 /news/YYYYMM/ 锚带 title）；2026-10-14 接入 |
| 新出行 | CN | EV/智驾社区，web_list（首页 /article/N 锚文本）；2026-10-14 接入 |
| 第一电动 | CN | EV 行业，web_list（首页 /carnews/ 锚文本）；2026-10-14 接入 |
| 量子位 | CN | AI 垂类同源替代（官网即公众号镜像），web_list + 汽车关键词门控（12 抓→2 净）；2026-10-14 接入 |
| 电动邦 | CN | EV/新能源行业，web_list（首页 /news/N.html 锚文本，相对+绝对通吃）；2026-10-14 接入 |
| 汽车之家 | CN | 门户综合，web_list + GBK 解码能力（新）；2026-10-14 接入 |
| 发现报告 · 交运设备 | CN | 券商研报（申万交运设备=汽车），json_api（SEO 端点 + 汽车词门控）；2026-10-15 接入 |
| 发现报告 · 电气设备 | CN | 券商研报（电动化/电池），json_api + 电动化词门控（4 抓→1 净）；2026-10-15 接入 |
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
| 盖世汽车 / 第一电动 | 无 RSS，但列表页静态可抓 → 已改走 web_list 接入（见二） |
| 42how | 文章列表 JS 渲染（静态 HTML 只有导航链接），web_list 不可用 |
| 车东西 / 晚点Auto / 机器之心 | JS 渲染，静态无文章链接（/feed 也是 SPA 壳）；候选 json_api 通道待摸 |
| 发现报告 搜索 API（searchListNoAuth） | 2026-08 起匿名返回「非VIP不能使用高级搜索」（带完整浏览器头同拒）；行业列表页 SSR 的 dataList 也是空（客户端拉取+VIP）。唯一免登录列表面=SEO 端点（见八），勿再试搜索接口 |
| 中汽协 caam.org.cn | 栏目页全是会员单位侧栏，新闻列表不可直达 |
| 工信部 miit.gov.cn | JS 壳页（5KB 无文章链接） |
| NHTSA API | 可用但美召回，中文读者价值低，暂缓 |
| Reddit RSS / rsshub.app 公网实例 | 超时（rsshub 需自托管，见下） |
| Hacker News Algolia query 通道 | ⚠️ 不可用于精确监控：typo 容忍 + 无 OR；只允许全量拉取后本地过滤 |

## 五、中文层策略

中文汽车科技媒体（车东西/智东西、42号车库、建约车评、电动星球、
汽车之心）几乎全部栖息在微信公众号，无 RSS。三条路
（2026-10-14 复测：RSSHub 公网 / wechat2rss 公共桥 / feeddd 均死，
搜狗微信搜索可达但反爬重；量子位官网证明「同源替代」路线可行
——接入一个号之前，先找它的官网/合作站镜像）：

1. **自托管 RSSHub**（M2，fnOS NAS Docker）——36kr 快讯、盖世、部分公众号
   的路由现成，公网实例不可用但自托管稳定；
2. **网页列表源扩展**（M1）——✅ 2026-10-14 首波落地：盖世/新出行/第一电动
   经 web_list 接入（修复 extract-web-items 两处回归后才可用）；
   待适配：中汽研、工信部政策页（JS 壳需换通道）；
   本轮探测淘汰：易车/车云/搜狐(壳或 502)、高工智能汽车(超时)、
   中国汽车报(JS 模板)、凤凰(锚点不可提取)、InsideEVs/Autoblog(RSS 404/403)。
3. **公众号专项**（M1+）——微信文章抓取通道。⚠️ 2026-01 腾讯发起
   网络级 DMCA（下架 4195 个仓库），chatlog 等解密工具链已死，自建桥
   路线经评估放弃；中期以「同源替代」为唯一可持续路径（量子位模式），
   纯公众号深度内容（建约车评类）接受缺口，长期或有商务合作路径。

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

## 八、公开 JSON API 通道（2026-10-15 落地）

`json_api` 源类型：站点若有免登录的公开 JSON 接口，`config/sources.json`
里一条配置即可接入，零代码。字段映射 + 点路径取列表，支持
`only_keywords`/`except_keywords` 门控与 rss/web_list 同语义：

```json
{
  "name": "发现报告 · 交运设备",
  "type": "json_api",
  "url": "https://api.fxbaogao.com/mofoun/seo/seoApiV3/listHomeIndustryReports?industry=%E4%BA%A4%E8%BF%90%E8%AE%BE%E5%A4%87",
  "path": "data",
  "title_field": "title",
  "date_field": "pubTimeStr",
  "url_template": "https://www.fxbaogao.com/detail/{docId}",
  "tier": 2, "weight": 0.95, "max": 6,
  "only_keywords": ["车", "电动", "…"],
  "except_keywords": ["晨会", "复盘"]
}
```

- `url_template`：列表项没有 url 字段只有 id 时，用 `{field}` 占位符
  拼详情页链接；引用字段缺失的条目整条丢弃。
- `date_field` 解析链：ISO 8601 → RFC 822 → 中文斜杠日期
  （`2026/10/13`，含尾斜杠变体）。
- 首个真实调用者（发现报告）暴露并修复了三个 M1 潜伏 bug
  （path 解析 4 参 hash-ref、date_field 键未符号化、#f 条目泄漏）——
  **通道没被真数据跑过就不算接入过**。

**找接口的方法**（fxbaogao 实战复盘）：Next.js 站先抓
`/_next/static/{buildId}/_buildManifest.js` 枚举页面 chunk，共享
chunk（commons/app）里 grep `"/mofoun/..."` 形态的路径；SSR 页面的
`__NEXT_DATA__` 本身就是免登录数据（fxData 含日/周/月热榜+27 行业
各 4 条最新，是候选后备面）；Java 后端的 400/1008 错误信息会泄露
DTO/枚举签名，可用来反推参数名。SPA 壳页（/rp 7KB 无 SSR）没有
接口线索，别在壳上浪费时间。

**候选清单**（有公开 JSON 接口或 `__NEXT_DATA__` 的站，逐个 curl
实测后走此通道）：

| 站 | 线索 | 状态 |
| --- | --- | --- |
| 36kr 快讯 | 官网 API 形态待查（feed 是 JS 壳） | 📋 待实测 |
| 智东西 | `__NEXT_DATA__` 候选 | 📋 待实测 |
| 车东西 / 晚点Auto | 同上 | 📋 待实测 |
| fxbaogao 日/周热榜 | 主页 `__NEXT_DATA__` fxData（dayTop/weekTopReports，但无发布日期字段，衰减按 48h 兜底） | 📋 观察中（研报主榜饱和后可再开） |
| fxbaogao 其他行业 | 27 个行业名换 URL 即可（机械设备=机器人/线控邻域） | 📋 候选 |
