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
