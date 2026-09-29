"use client";

import { useEffect, useState } from "react";
import { NATIVE_NAMES, localeCookie, normalizeLocaleTag, setActiveLocale, t } from "../../lib/i18n";

declare global {
  interface Window {
    __EDUFLOW_MESSAGES__?: { locale: string; catalog: unknown; supported: string[] };
  }
}

export function ThemeToggle() {
  const [dark, setDark] = useState(false);
  const [locale, setLocale] = useState("en");
  const [supported, setSupported] = useState<string[]>(["en"]);

  useEffect(() => {
    setDark(document.documentElement.dataset.theme === "dark");
    setLocale(document.documentElement.lang || "en");
    const list = window.__EDUFLOW_MESSAGES__?.supported;
    if (Array.isArray(list) && list.length) setSupported(list);
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
    <>
    <span className="auth-top-left select-wrap lang-wrap">
    <select
      className="btn btn-light btn-sm auth-lang-select"
      aria-label={t("theme.language")}
      value={locale}
      onChange={(event) => {
        const next = normalizeLocaleTag(event.target.value) ?? "en";
        document.cookie = localeCookie(next);
        setLocale(next);
        setActiveLocale(next);
        document.documentElement.lang = next;
        window.location.reload();
      }}
    >
      {supported.map((code) => <option key={code} value={code}>{NATIVE_NAMES[code] ?? code}</option>)}
    </select>
    </span>
    <button
      className={`theme-toggle auth-top-right${dark ? " is-dark" : ""}`}
      type="button"
      aria-label={dark ? t("theme.toLight") : t("theme.toDark")}
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
    </>
  );
}
