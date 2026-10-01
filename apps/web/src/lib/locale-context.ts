"use client";

import { createContext, useContext } from "react";

/**
 * Aktive Sprache für Client-Komponenten. Der LocaleProvider liefert sie;
 * wer `useLocale()` aufruft, rendert bei einem Sprachwechsel neu — nötig,
 * weil `t()` aus einem Modul-Zustand liest und ein erneuter Render der
 * Kindelemente sonst an deren unveränderten Element-Referenzen abprallt.
 */
export const LocaleContext = createContext<string>("en");

/** Aktive Sprache (für `t()`-Aufrufer als Abonnement gedacht). */
export function useLocale(): string {
  return useContext(LocaleContext);
}
