"use client";

import { useEffect, useRef, useState } from "react";
import { LOCALE_EVENT, NATIVE_NAMES, localeCookie, normalizeLocaleTag, setActiveLocale, t } from "../../lib/i18n";
import { useLocale } from "../../lib/locale-context";

declare global {
  interface Window {
    __EDUFLOW_MESSAGES__?: { locale: string; catalog: unknown; supported: string[]; coverage?: Array<{ code: string; percent: number }> };
  }
}

export function ThemeToggle() {
  const [dark, setDark] = useState(false);
  const [locale, setLocale] = useState("en");
  const [supported, setSupported] = useState<string[]>(["en"]);
  const [coverage, setCoverage] = useState<Record<string, number>>({});
  const [langOpen, setLangOpen] = useState(false);
  const langRef = useRef<HTMLDivElement>(null);
  useLocale(); // abonniert den Sprachwechsel, damit die Beschriftungen neu rendern

  useEffect(() => {
    setDark(document.documentElement.dataset.theme === "dark");
    setLocale(document.documentElement.lang || "en");
    const list = window.__EDUFLOW_MESSAGES__?.supported;
    if (Array.isArray(list) && list.length) setSupported(list);
    const rows = window.__EDUFLOW_MESSAGES__?.coverage;
    if (Array.isArray(rows)) {
      const map: Record<string, number> = {};
      for (const row of rows) {
        if (row && typeof row.code === "string" && typeof row.percent === "number") map[row.code] = row.percent;
      }
      setCoverage(map);
    }
  }, []);

  useEffect(() => {
    if (!langOpen) return;
    function onDown(event: MouseEvent) {
      if (langRef.current && !langRef.current.contains(event.target as Node)) setLangOpen(false);
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setLangOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [langOpen]);

  async function pickLanguage(code: string) {
    const wanted = normalizeLocaleTag(code) ?? "en";
    setLangOpen(false);
    try {
      const response = await fetch(`/api/locale?lang=${encodeURIComponent(wanted)}`, { cache: "no-store" });
      const data = (await response.json()) as { locale?: string; catalog?: unknown };
      const next = typeof data.locale === "string" ? data.locale : wanted;
      const prev = window.__EDUFLOW_MESSAGES__;
      window.__EDUFLOW_MESSAGES__ = {
        locale: next,
        catalog: data.catalog ?? prev?.catalog,
        supported: prev?.supported ?? [],
        coverage: prev?.coverage,
      };
      document.cookie = localeCookie(next);
      setLocale(next);
      setActiveLocale(next);
      document.documentElement.lang = next;
      window.dispatchEvent(new Event(LOCALE_EVENT));
    } catch {
      document.cookie = localeCookie(wanted);
      window.location.reload();
    }
  }

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
    <div className="auth-top-left lang-wrap" ref={langRef}>
    <button
      type="button"
      className="btn btn-light btn-sm lang-btn"
      aria-haspopup="menu"
      aria-expanded={langOpen}
      aria-label={t("theme.language")}
      onClick={() => setLangOpen((open) => !open)}
    >
      {NATIVE_NAMES[locale] ?? locale}
    </button>
    {langOpen && (
      <div className="profile-menu lang-menu" role="menu" aria-label={t("theme.language")}>
        {supported.map((code) => {
          const percent = coverage[code];
          return (
            <button
              key={code}
              type="button"
              role="menuitemradio"
              aria-checked={code === locale}
              className="pm-link lang-option"
              onClick={() => pickLanguage(code)}
            >
              <span className="lang-row">
                <span>{NATIVE_NAMES[code] ?? code}</span>
                {percent !== undefined && <span className="lang-pct">{percent} %</span>}
              </span>
              {percent !== undefined && (
                <span className="lang-bar" aria-hidden="true">
                  <span style={{ width: `${percent}%` }} />
                </span>
              )}
            </button>
          );
        })}
      </div>
    )}
    </div>
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
