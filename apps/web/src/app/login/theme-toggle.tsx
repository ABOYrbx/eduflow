"use client";

import { useEffect, useState } from "react";

export function ThemeToggle() {
  const [dark, setDark] = useState(false);

  useEffect(() => {
    setDark(document.documentElement.dataset.theme === "dark");
  }, []);

  function toggleTheme() {
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("theme", next);
    } catch {
      // Theme still changes for this page when storage is unavailable.
    }
    setDark(next === "dark");
  }

  return (
    <button
      className={`theme-toggle auth-top-right${dark ? " is-dark" : ""}`}
      type="button"
      aria-label={dark ? "Zum hellen Modus wechseln" : "Zum dunklen Modus wechseln"}
      aria-pressed={dark}
      onClick={toggleTheme}
    >
      <span className="theme-toggle-thumb" aria-hidden="true">
        <svg className="theme-toggle-icon theme-icon-moon" viewBox="0 0 24 24" fill="none">
          <path d="M20.2 15.2A8.2 8.2 0 0 1 8.8 3.8 8.5 8.5 0 1 0 20.2 15.2Z" />
        </svg>
        <svg className="theme-toggle-icon theme-icon-sun" viewBox="0 0 24 24" fill="none">
          <circle cx="12" cy="12" r="3.7" />
          <path d="M12 2v2m0 16v2M4.93 4.93l1.42 1.42m11.3 11.3 1.42 1.42M2 12h2m16 0h2M4.93 19.07l1.42-1.42m11.3-11.3 1.42-1.42" />
        </svg>
      </span>
    </button>
  );
}
