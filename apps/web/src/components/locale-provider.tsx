"use client";

import { useEffect, useReducer } from "react";
import { setActiveLocale } from "../lib/i18n";

/**
 * Schaltet Client-Komponenten nach der Hydration auf die vom Server
 * eingespritzte Sprache um. Der erste Render bleibt deutsch (= Server-HTML),
 * erst der Effekt danach aktiviert die Sprache — keine Hydration-Warnung.
 */
export function LocaleProvider({ children }: { children: React.ReactNode }) {
  const [, force] = useReducer((count: number) => count + 1, 0);
  useEffect(() => {
    const locale = window.__EDUFLOW_MESSAGES__?.locale ?? null;
    if (locale && locale !== "de") {
      setActiveLocale(locale);
      force();
    }
  }, []);
  return <>{children}</>;
}
