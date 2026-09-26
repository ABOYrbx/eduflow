import { createHash, randomBytes } from "node:crypto";

/** Opake Tokens wie Python (`api/core.py`, Paket N-A).
 *
 * Format: `secrets.token_urlsafe(32)`-äquivalent (43 base64url-Zeichen),
 * Ablauf als `YYYY-MM-DD HH:MM:SS` (Ortszeit, wie `datetime.now()`).
 * Gespeichert wird nur der SHA-256-Hash (Tabelle `ApiToken`).
 */
export const OPAQUE_TOKEN_DAYS = Number.parseInt(process.env.EDUFLOW_API_TOKEN_DAYS ?? "30", 10) || 30;

export function newOpaqueToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

const pad = (value: number): string => String(value).padStart(2, "0");

export function formatDateTime(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

export function opaqueExpiry(days: number = OPAQUE_TOKEN_DAYS): Date {
  return new Date(Date.now() + Math.max(0, days) * 24 * 60 * 60 * 1000);
}
