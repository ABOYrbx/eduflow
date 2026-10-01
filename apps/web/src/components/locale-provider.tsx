"use client";

import { useEffect, useState } from "react";
import { LOCALE_EVENT, setActiveLocale } from "../lib/i18n";
import { LocaleContext } from "../lib/locale-context";

/**
 * Schaltet Client-Komponenten nach der Hydration auf die vom Server
 * eingespritzte Sprache um. Der erste Render bleibt englisch (= Server-HTML),
 * erst der Effekt danach aktiviert die Sprache — keine Hydration-Warnung.
 *
 * Die aktive Sprache steckt im Context: nur so rendern Komponenten neu, wenn
 * sich `t()`-Werte ändern. Ein erzwungener Render dieses Providers allein
 * reicht nicht, weil React bei unveränderten Kind-Elementen den Teilbaum
 * überspringt.
 */
export function LocaleProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState<string | null>(null);

  useEffect(() => {
    function apply(next: string | null): void {
      setActiveLocale(next);
      setLocale(next);
    }
    apply(window.__EDUFLOW_MESSAGES__?.locale ?? null);
    function onLocaleChange(): void {
      apply(window.__EDUFLOW_MESSAGES__?.locale ?? null);
    }
    window.addEventListener(LOCALE_EVENT, onLocaleChange);
    return () => window.removeEventListener(LOCALE_EVENT, onLocaleChange);
  }, []);

  return <LocaleContext.Provider value={locale ?? "en"}>{children}</LocaleContext.Provider>;
}
