"use client";

import { useEffect, useRef, useState } from "react";
import { LOCALE_EVENT, NATIVE_NAMES, localeCookie, normalizeLocaleTag, setActiveLocale, t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";

declare global {
  interface Window {
    __EDUFLOW_MESSAGES__?: { locale: string; catalog: unknown; supported: string[]; coverage?: Array<{ code: string; percent: number }> };
  }
}

/**
 * Sprachwahl als Pille mit eigenem Menü (Profilmenü-Stil) inklusive
 * Übersetzungsstand je Sprache. Wird auf der Login-Seite oben links und
 * in den Einstellungen genutzt; `className` steuert nur die Breite.
 */
export function LanguagePicker({ className = "" }: { className?: string }) {
  const active = useLocale();
  const [supported, setSupported] = useState<string[]>(["en"]);
  const [coverage, setCoverage] = useState<Record<string, number>>({});
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
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
    if (!open) return;
    function onDown(event: MouseEvent) {
      if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false);
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  async function pickLanguage(code: string) {
    const wanted = normalizeLocaleTag(code) ?? "en";
    setOpen(false);
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
      setActiveLocale(next);
      document.documentElement.lang = next;
      window.dispatchEvent(new Event(LOCALE_EVENT));
    } catch {
      document.cookie = localeCookie(wanted);
      window.location.reload();
    }
  }

  return (
    <div className={`lang-wrap${className ? ` ${className}` : ""}`} ref={ref}>
      <button
        type="button"
        className="btn btn-light btn-sm lang-btn"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={t("theme.language")}
        onClick={() => setOpen((value) => !value)}
      >
        {NATIVE_NAMES[active] ?? active}
      </button>
      {open && (
        <div className="profile-menu lang-menu" role="menu" aria-label={t("theme.language")}>
          {supported.map((code) => {
            const percent = coverage[code];
            return (
              <button
                key={code}
                type="button"
                role="menuitemradio"
                aria-checked={code === active}
                className="pm-link lang-option"
                onClick={() => void pickLanguage(code)}
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
  );
}
