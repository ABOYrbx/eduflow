/* Theme-Steuerung: "light"/"dark" = explizite Wahl aus localStorage,
   alles andere (kein Wert/"system") = System folgen (prefers-color-scheme,
   live bei Systemwechsel). Öffentliche API für die Einstellungsseite:
   window.EduFlowTheme = {choice(), setChoice(v), accent(), setAccent(v)}. */
(function () {
  function storedChoice() {
    try { return localStorage.getItem("theme"); } catch (e) { return null; }
  }
  function effectiveTheme() {
    var s = storedChoice();
    if (s === "light" || s === "dark") return s;
    try {
      return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    } catch (e) { return "light"; }
  }
  function applyTheme() {
    document.documentElement.dataset.theme = effectiveTheme();
  }
  function paint() {
    paintAccents();
  }
  /* Akzentfarbe: Wahl aus localStorage (Schwarz = Standard = kein Attribut). */
  function currentAccent() {
    return document.documentElement.dataset.accent || "black";
  }
  function paintAccents() {
    var cur = currentAccent();
    document.querySelectorAll(".accent-dot").forEach(function (b) {
      b.classList.toggle("active", b.dataset.setAccent === cur);
    });
  }
  function setAccent(v) {
    v = v || "black";
    if (v === "black") {
      document.documentElement.removeAttribute("data-accent");
      try { localStorage.removeItem("accent"); } catch (e) {}
    } else {
      document.documentElement.dataset.accent = v;
      try { localStorage.setItem("accent", v); } catch (e) {}
    }
    paintAccents();
  }
  function initAccents() {
    paintAccents();
    document.querySelectorAll(".accent-dot").forEach(function (b) {
      b.addEventListener("click", function () {
        setAccent(b.dataset.setAccent || "black");
      });
    });
  }
  function setChoice(v) {
    // "system" = kein gespeicherter Wert -> System live folgen.
    try {
      if (v === "system") localStorage.removeItem("theme");
      else localStorage.setItem("theme", v === "dark" ? "dark" : "light");
    } catch (e) {}
    applyTheme();
    paint();
  }
  // Einstellungsseite (+ künftige Stellen) nutzen diese API.
  window.EduFlowTheme = {
    choice: function () { return storedChoice() || "system"; },
    setChoice: setChoice,
    accent: currentAccent,
    setAccent: setAccent,
  };
  // Systemwechsel live übernehmen, solange keine explizite Wahl gespeichert ist.
  try {
    var mq = window.matchMedia("(prefers-color-scheme: dark)");
    var onSys = function () { if (!storedChoice()) { applyTheme(); paint(); } };
    if (mq.addEventListener) mq.addEventListener("change", onSys);
    else if (mq.addListener) mq.addListener(onSys);
  } catch (e) {}
  function initThemeControls() {
    applyTheme();
    paint();
    initAccents();
    initCompactNav();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initThemeControls, { once: true });
  } else {
    initThemeControls();
  }

  /* Kompakte Navi beim Scrollen: verkleinert die Bar auf die drei
     Haupt-Links (Nachrichten / Hausaufgaben / Stundenplan). */
  function initCompactNav() {
    var nav = document.querySelector(".nav-wrap");
    if (!nav) return;
    var ticking = false;
    function update() {
      ticking = false;
      var y = window.scrollY || window.pageYOffset || 0;
      nav.classList.toggle("is-compact", y > 24);
    }
    function onScroll() {
      if (!ticking) { ticking = true; requestAnimationFrame(update); }
    }
    update();
    window.addEventListener("scroll", onScroll, { passive: true });
  }
})();
