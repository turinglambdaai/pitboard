#lang scribble/manual

@title[#:tag "pitboard"]{pitboard}
@author{turinglambdaai}

@defmodule[pitboard]

汽车行业每日热点日报引擎：抓取 RSS 媒体源、GitHub 汽车话题仓库与 arXiv
论文，聚簇去重，按独立来源数与时间衰减计算热度，输出站点、RSS、JSON
API、Markdown 日报与 llms.txt。设计灵感致谢
@hyperlink["https://github.com/KKKKhazix/AIHOT"]{AIHOT}。

@section[#:tag "cli"]{命令行}

@verbatim{
raco pitboard fetch  [--date YYYY-MM-DD] [--data DIR] [--config FILE] [--no-llm]
raco pitboard serve  [--port N] [--data DIR] [--assets DIR]
raco pitboard export [--out DIR] [--data DIR] [--domain D] [--base-url U]
}

@section[#:tag "llm"]{LLM 增强（可选）}

设置 @envvar{PITBOARD_LLM_API_KEY}（必填）、@envvar{PITBOARD_LLM_BASE_URL}
（默认 @tt{https://api.deepseek.com}）、@envvar{PITBOARD_LLM_MODEL}
（默认 @tt{deepseek-chat}），任何 OpenAI 兼容接口均可。未配置时引擎以
纯排序模式运行，站点功能不受影响。

@section[#:tag "api"]{Agent 出口}

@itemlist[
 @item{@tt{/rss.xml} — RSS 2.0}
 @item{@tt{/api/v1/latest.json} 与 @tt{/api/v1/digest/<date>.json}}
 @item{@tt{/daily/<date>.md} — Markdown 日报}
 @item{@tt{/llms.txt} — 站点索引}
 @item{@tt{/api/events} — SSE 出刊推送}]
