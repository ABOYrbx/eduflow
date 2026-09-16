/* Theme-Umschalter: folgt beim ersten Besuch dem System (prefers-color-scheme),
   danach gilt die gespeicherte Wahl aus localStorage. */
(function () {
  function current() {
    return document.documentElement.dataset.theme === "dark" ? "dark" : "light";
  }
  function paint() {
    var dark = current() === "dark";
    document.querySelectorAll(".theme-toggle").forEach(function (b) {
      b.textContent = dark ? "☀" : "☾";
      b.setAttribute("aria-label", dark ? "Zum hellen Modus wechseln" : "Zum dunklen Modus wechseln");
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    paint();
    document.querySelectorAll(".theme-toggle").forEach(function (b) {
      b.addEventListener("click", function () {
        var next = current() === "dark" ? "light" : "dark";
        document.documentElement.dataset.theme = next;
        try { localStorage.setItem("theme", next); } catch (e) {}
        paint();
      });
    });
  });
})();
