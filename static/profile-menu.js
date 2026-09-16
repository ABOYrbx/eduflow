/* Profil-Dropdown: Klick auf den Avatar öffnet/schließt das Menü,
   Klick daneben oder Escape schließt es. */
(function () {
  function closeAll() {
    document.querySelectorAll(".profile-wrap.open").forEach(function (w) {
      w.classList.remove("open");
      var btn = w.querySelector(".avatar-btn");
      if (btn) btn.setAttribute("aria-expanded", "false");
    });
  }
  document.addEventListener("click", function (e) {
    var btn = e.target.closest ? e.target.closest(".avatar-btn") : null;
    if (btn) {
      var wrap = btn.closest(".profile-wrap");
      var willOpen = !wrap.classList.contains("open");
      closeAll();
      if (willOpen) {
        wrap.classList.add("open");
        btn.setAttribute("aria-expanded", "true");
      }
      return;
    }
    if (e.target.closest && !e.target.closest(".profile-menu")) closeAll();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closeAll();
  });
})();
