import { t } from "./i18n";
import type { ApiError } from "./types";

/** Weg zur Anmeldung. Der Server-Gate dort (`lib/session.ts`) prüft neu. */
export const LOGIN_PATH = "/login";

/**
 * Einziger Datenweg der Web-UI: immer relativ, nie direkt zur API.
 * Der Browser sieht keine Tokens — httpOnly-Cookies und der Bearer-Header
 * stecken ausschließlich im Proxy (`app/api/v1/[...path]/route.ts`).
 *
 * `401` heißt: Sitzung ungültig oder abgelaufen. Der Proxy hat die
 * Cookies dann bereits geleert, also gehen wir zurück zur Anmeldung
 * (Hausregel: 401 überall → Login). `window.location` statt Router, damit
 * auch der Server-Gate neu läuft und der Zustand nicht im Client bleibt.
 */
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`/api/v1${path}`, {
    ...init,
    cache: "no-store",
    headers: { ...(init?.body ? { "content-type": "application/json" } : {}), ...init?.headers },
  });
  const body = (await response.json().catch(() => ({}))) as T & ApiError;
  if (!response.ok) {
    if (response.status === 401) window.location.replace(LOGIN_PATH);
    throw new Error(body.error ?? t("common.requestFailed"));
  }
  return body;
}
