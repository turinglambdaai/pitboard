/* pitboard — theme toggle, filters, search, SSE edition notifications.
   No dependencies. */
(function () {
  "use strict";

  /* ---- theme ---- */
  function applyTheme(t) {
    document.documentElement.setAttribute("data-theme", t);
    try { localStorage.setItem("pitboard-theme", t); } catch (e) {}
  }
  try {
    var saved = localStorage.getItem("pitboard-theme");
    if (saved) {
      applyTheme(saved);
    } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
      applyTheme("dark");
    }
  } catch (e) {}

  var btn = document.getElementById("theme-btn");
  if (btn) {
    btn.addEventListener("click", function () {
      var cur = document.documentElement.getAttribute("data-theme");
      applyTheme(cur === "dark" ? "light" : "dark");
    });
  }

  /* ---- filters + search ---- */
  var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".tab"));
  var search = document.getElementById("search");
  var active = "all";

  function applyFilter() {
    var q = search && search.value ? search.value.toLowerCase() : "";
    cards.forEach(function (c) {
      var okKind = active === "all" || c.getAttribute("data-kind") === active;
      var okText = !q || (c.getAttribute("data-text") || "").indexOf(q) !== -1;
      c.style.display = okKind && okText ? "" : "none";
    });
    // per-tab counts stay global (not search-aware)
    tabs.forEach(function (t) {
      var k = t.getAttribute("data-filter");
      var n = cards.filter(function (c) {
        return k === "all" || c.getAttribute("data-kind") === k;
      }).length;
      var badge = t.querySelector(".tab-n");
      if (badge) badge.textContent = n;
    });
  }

  if (cards.length && (tabs.length || search)) {
    tabs.forEach(function (t) {
      t.addEventListener("click", function () {
        active = t.getAttribute("data-filter") || "all";
        tabs.forEach(function (x) { x.classList.remove("active"); });
        t.classList.add("active");
        applyFilter();
      });
    });
    if (search) {
      search.addEventListener("input", applyFilter);
      document.addEventListener("keydown", function (e) {
        if (e.key === "/" && document.activeElement !== search &&
            !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {
          e.preventDefault();
          search.focus();
        }
      });
    }
    applyFilter();
  }

  /* ---- SSE edition notifications ---- */
  function showEditionBar(date) {
    var bar = document.getElementById("edition-bar");
    if (!bar) {
      bar = document.createElement("div");
      bar.id = "edition-bar";
      bar.innerHTML = "<span></span><button type=\"button\">刷新</button>";
      document.body.appendChild(bar);
      bar.querySelector("button").addEventListener("click", function () {
        location.reload();
      });
    }
    bar.style.display = "flex";
    var label = bar.querySelector("span");
    if (label) label.textContent = date ? "新一期已出刊：" + date : "新一期已出刊";
  }

  if (window.EventSource) {
    try {
      var es = new EventSource("/api/events");
      es.addEventListener("edition", function (ev) {
        var date = null;
        try { date = JSON.parse(ev.data).date; } catch (e) {}
        showEditionBar(date);
      });
    } catch (e) { /* static mirror or blocked — fine */ }
  }
})();

/* ---- bookmarks (localStorage, M3) ---- */
(function () {
  var KEY = "pitboard-bookmarks";
  function load() { try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch (e) { return []; } }
  function save(list) { try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {} }
  var marks = load();
  document.querySelectorAll(".card").forEach(function (card) {
    var link = card.querySelector(".card-title a");
    if (!link) return;
    var url = link.getAttribute("href");
    var btn = document.createElement("button");
    btn.className = "bookmark-btn";
    btn.type = "button";
    btn.setAttribute("aria-label", "收藏");
    var marked = marks.some(function (m) { return m.u === url; });
    btn.textContent = marked ? "★" : "☆";
    btn.addEventListener("click", function () {
      marks = load();
      if (marks.some(function (m) { return m.u === url; })) {
        marks = marks.filter(function (m) { return m.u !== url; });
        btn.textContent = "☆";
      } else {
        marks.push({ u: url, t: link.textContent, d: new Date().toISOString() });
        btn.textContent = "★";
      }
      save(marks);
    });
    card.querySelector(".card-top").appendChild(btn);
  });
})();

/* ---- install sentence copy (about page) ---- */
(function () {
  var copyBtn = document.getElementById("copy-install");
  if (copyBtn) {
    copyBtn.addEventListener("click", function () {
      var sentence = "请安装 pitboard 技能：https://pitboard.jrtx.site/skill/pitboard/SKILL.md";
      function done() {
        copyBtn.textContent = "已复制 ✓ 发给你的 agent";
        setTimeout(function () { copyBtn.textContent = "复制安装语"; }, 2000);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(sentence).then(done, function () { fallback(); });
      } else {
        fallback();
      }
      function fallback() {
        var ta = document.createElement("textarea");
        ta.value = sentence;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  }
})();

/* ---- i18n: zh default, EN via nav button -------------------------------- */
(function () {
  var I18N = {
    en: {
      "nav.today": "Today", "nav.topics": "Topics", "nav.bookmarks": "Saved",
      "nav.archive": "Archive", "nav.about": "About",
      "footer.tagline": "Automotive industry daily digest · Racket full-stack, self-hosted · auto-published daily",
      "footer.license": "MIT licensed", "footer.rss": "RSS feed",
      "meta.hot": " hot topics", "meta.items": " source items", "meta.sources": " sources",
      "board.sub": "PITBOARD · DAILY",
      "quick.label": "CURRENT HOT",
      "index.empty": "Not enough hot topics today.",
      "lane.opensource": "Open Source Radar",
      "tab.all": "All", "tab.github": "Repos", "tab.news": "News", "tab.papers": "Papers",
      "toolbar.hint": "Ranked by independent sources",
      "search.placeholder": "Search titles / summaries… (press /)",
      "kind.news": "News", "kind.github": "Repo", "kind.paper": "Paper",
      "chip.new": "New", "chip.rising": "↑ Rising", "chip.progress": "Update",
      "card.sources": " independent sources", "card.seen": "First seen ",
      "card.more1": "Show all ", "card.more2": " sources", "card.track": "Track →",
      "topics.title": "Topic Radar", "topics.meta": "Cross-edition tracking of every story that matters.",
      "topic.meta": " related items · cross-edition tracking",
      "period.meta1": "Compiled from the daily digest · ",
      "period.meta2": " top stories · deduped by heat",
      "period.archive": " Archive", "period.stories": " stories",
      "archive.title": "Archive", "archive.hot": " hot topics",
      "empty.title": "No edition yet", "empty.hint": "Run the first fetch:",
      "notfound.title": "Nothing on this board",
      "notfound.back": "← Back to today",
      "about.how": "How it works", "about.agents": "Agent endpoints",
      "about.selfhost": "Self-hosting", "about.license": "License",
      "about.selfhost.body": "One Racket process, zero external dependencies (no database):",
      "install.kicker": "One-sentence install",
      "install.hint": "Send that line to your agent (Claude Code, ZCode, …) — it installs itself."
    }
  };
  function setLang(lang) {
    document.documentElement.lang = lang === "en" ? "en" : "zh-CN";
    var dict = I18N[lang] || {};
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var k = el.getAttribute("data-i18n");
      if (dict[k]) el.textContent = dict[k];
    });
    document.querySelectorAll("[data-i18n-placeholder]").forEach(function (el) {
      var k = el.getAttribute("data-i18n-placeholder");
      if (dict[k]) el.setAttribute("placeholder", dict[k]);
    });
    var btn = document.getElementById("lang-btn");
    if (btn) btn.textContent = lang === "en" ? "中" : "EN";
    try { localStorage.setItem("pitboard-lang", lang); } catch (e) {}
  }
  var langBtn = document.getElementById("lang-btn");
  if (langBtn) {
    langBtn.addEventListener("click", function () {
      var cur;
      try { cur = localStorage.getItem("pitboard-lang"); } catch (e) {}
      setLang(cur === "en" ? "zh" : "en");
    });
    var saved = null;
    try { saved = localStorage.getItem("pitboard-lang"); } catch (e) {}
    if (saved === "en") setLang("en");
  }
})();

/* ---- bookmarks page (exported bookmark manager) ---- */
(function () {
  "use strict";
  var imp = document.getElementById("imp");
  if (!imp) return;
  var list = document.getElementById("list");
  var KEY = "pitboard-bookmarks";
  function load() {
    try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch (e) { return []; }
  }
  function save(l) {
    try { localStorage.setItem(KEY, JSON.stringify(l)); } catch (e) {}
  }
  function render() {
    var l = load();
    list.innerHTML = "";
    if (!l.length) {
      list.innerHTML = '<li class="topic-row"><span class="src-dom">还没有书签——在今日榜卡片上点 ☆ 收藏</span></li>';
      return;
    }
    l.forEach(function (m) {
      var li = document.createElement("li");
      li.className = "topic-row";
      li.innerHTML = '<span class="topic-date">' + (m.d || "") + '</span><a href="' + m.u + '" target="_blank" rel="noopener">' + m.t + '</a><span class="src-dom">移除</span>';
      var rm = li.querySelector(".src-dom");
      rm.style.cursor = "pointer";
      rm.addEventListener("click", function () {
        save(load().filter(function (x) { return x.u !== m.u; }));
        render();
      });
      list.appendChild(li);
    });
  }
  document.getElementById("clr").addEventListener("click", function () { save([]); render(); });
  document.getElementById("exp").addEventListener("click", function () {
    var blob = new Blob([JSON.stringify(load(), null, 2)], { type: "application/json" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "pitboard-bookmarks.json";
    a.click();
  });
  imp.addEventListener("change", function (ev) {
    var f = ev.target.files[0];
    if (!f) return;
    var r = new FileReader();
    r.onload = function () {
      try {
        var inc = JSON.parse(r.result);
        var l = load();
        inc.forEach(function (m) {
          if (m && m.u && !l.some(function (x) { return x.u === m.u; })) l.push(m);
        });
        save(l);
        render();
      } catch (e) { alert("导入失败：不是有效的书签 JSON"); }
    };
    r.readAsText(f);
  });
  render();
})();

/* ---- search page ---- */
(function () {
  "use strict";
  var q = document.getElementById("q");
  var results = document.getElementById("results");
  if (!q || !results) return;
  var IDX = null;
  function run() {
    var query = q.value.trim().toLowerCase();
    if (!IDX) return;
    results.innerHTML = "";
    if (!query) return;
    var n = 0;
    IDX.forEach(function (it) {
      if (n >= 30) return;
      if (it.t.toLowerCase().indexOf(query) !== -1) {
        n++;
        var li = document.createElement("li");
        li.className = "topic-row";
        li.innerHTML = '<span class="topic-date">' + it.d + '</span><a href="' + it.u + '" target="_blank" rel="noopener">' + it.t + '</a><span class="src-dom">' + it.k + ' · 🔥' + it.h + '</span>';
        results.appendChild(li);
      }
    });
    if (!n) results.innerHTML = '<li class="topic-row"><span class="src-dom">没有匹配内容</span></li>';
  }
  fetch("/search-index.json").then(function (r) { return r.json(); }).then(function (j) {
    IDX = [];
    j.forEach(function (day) {
      day.forEach(function (c) { IDX.push({ d: c.d, t: c.t, u: c.u, k: c.k, h: c.h }); });
    });
    run();
  });
  q.addEventListener("input", run);
})();
