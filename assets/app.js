/* pitboard — theme toggle + SSE edition notifications. No dependencies. */
(function () {
  "use strict";

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
