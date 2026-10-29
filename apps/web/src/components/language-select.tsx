"use client";

import { useEffect, useRef, useState } from "react";
import { LOCALE_COOKIE, NATIVE_NAMES, normalizeLocaleTag, t } from "../lib/i18n";
import { LOCALE_COVERAGE } from "../lib/locale-coverage.generated";

declare global {
  interface Window {
    __EDUFLOW_MESSAGES__?: { locale: string; catalog: unknown; supported: string[] };
  }
}

function percentFor(code: string): number {
  return LOCALE_COVERAGE.find((row) => row.code === code)?.percent ?? 0;
}

/**
 * Sprachauswahl oben links auf der Login-Seite: aktuelle Sprache mit
 * Übersetzungsstand, Dropdown mit allen Sprachen und Prozentbalken.
 * Auswahl schreibt ein Cookie und lädt neu (Server rendert dann lokalisiert).
 */
export function LanguageSelect() {
  const [locale, setLocale] = useState("en");
  const [supported, setSupported] = useState<string[]>(LOCALE_COVERAGE.map((row) => row.code));
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setLocale(document.documentElement.lang || "en");
    const list = window.__EDUFLOW_MESSAGES__?.supported;
    if (Array.isArray(list) && list.length) {
      setSupported(Array.from(new Set([...list, ...LOCALE_COVERAGE.map((row) => row.code)])));
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: PointerEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open ]);

  function choose(code: string) {
    const next = normalizeLocaleTag(code) ?? "en";
    document.cookie = `${LOCALE_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;
    window.location.reload();
  }

  const ordered = [...supported].sort((a, b) => {
    if (a === locale) return -1;
    if (b === locale) return 1;
    return (NATIVE_NAMES[a] ?? a).localeCompare(NATIVE_NAMES[b] ?? b, "en");
  });

  return (
    <div className="auth-top-left lang-select" ref={rootRef}>
      <button
        className="lang-button"
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={t("theme.language")}
        onClick={() => setOpen((value) => !value)}
      >
        <svg className="lang-globe" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <circle cx="12" cy="12" r="9" />
          <path d="M3 12h18M12 3c2.5 2.6 3.9 5.7 3.9 9S14.5 18.4 12 21c-2.5-2.6-3.9-5.7-3.9-9S9.5 5.6 12 3Z" />
        </svg>
        <span className="lang-current">{NATIVE_NAMES[locale] ?? locale}</span>
        <span className="lang-pct" aria-hidden="true">{percentFor(locale)}&thinsp;%</span>
      </button>
      {open && (
        <div className="lang-menu" role="menu">
          {ordered.map((code) => (
            <button
              key={code}
              className={`lang-option${code === locale ? " active" : ""}`}
              type="button"
              role="menuitemradio"
              aria-checked={code === locale}
              onClick={() => choose(code)}
            >
              <span className="lang-name">{NATIVE_NAMES[code] ?? code}</span>
              <span className="lang-pct">{percentFor(code)}&thinsp;%</span>
              <span className="lang-bar" aria-hidden="true">
                <span className="lang-fill" style={{ width: `${percentFor(code)}%` }} />
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
