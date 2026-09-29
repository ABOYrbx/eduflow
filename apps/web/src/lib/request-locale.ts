import { cookies, headers } from "next/headers";
import "./locales";
import { LOCALE_COOKIE, parseAcceptLanguage, resolveLocale } from "./i18n";

/**
 * Sprache für den aktuellen Request (nur Server-Komponenten/Layout).
 * Reihenfolge: Cookie `eduflow_locale` → Accept-Language → Englisch.
 */
export async function requestLocale(): Promise<string> {
  const store = await cookies();
  const headerList = await headers();
  return resolveLocale([
    store.get(LOCALE_COOKIE)?.value ?? null,
    ...parseAcceptLanguage(headerList.get("accept-language")),
  ]);
}
