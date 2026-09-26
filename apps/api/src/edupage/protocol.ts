import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import { Base64DecodeError } from "./errors";

/** Exakt wie `urllib.parse.quote` (Standard, `safe='/'`): Slash bleibt offen,
 *  `!'()*` werden kodiert (encodeURIComponent lässt sie stehen).
 */
export function quote(value: string): string {
  return encodeURIComponent(value)
    .replace(/%2F/gi, "/")
    .replace(/[!'()*]/g, (ch) => `%${ch.charCodeAt(0).toString(16).toUpperCase()}`);
}

export function encodeFormData(data: Record<string, string>): string {
  return Object.entries(data).map(([key, value]) => `${quote(key)}=${quote(value)}`).join("&");
}

/** RPC-Body wie `RequestData.encode_request_body` (deflate-raw + btoa + sha1). */
export function encodeRequestBody(data: Record<string, string>): string {
  const form = encodeFormData(data);
  const compressed = deflateRawSync(Buffer.from(form, "utf8"), { level: 6 });
  const encoded = compressed.toString("base64");
  const eqap = `dz:${encoded}`;
  const dataHash = createHash("sha1").update(eqap, "utf8").digest("hex");
  return encodeFormData({ eqap, eqacs: dataHash, eqaz: "1" });
}

const stripWhitespace = (value: string): string => value.replace(/[\t\n\f\r ]/g, "");

/** Antwort dekodieren wie `RequestData.decode_response` (`eqwd:`/`eqz:`/roh).
 *
 * Exakt wie Python: nur base64→latin1, kein Inflate (die Lib dekomprimiert
 * Antworten nie — `eqz:` ist reines base64-Wrapping).
 */
export function decodeResponse(response: string): string {
  if (response.startsWith("eqwd:")) {
    return Buffer.from(stripWhitespace(response.slice(5)), "base64").toString("utf8");
  }
  if (!response.startsWith("eqz:")) return response;
  try {
    return Buffer.from(stripWhitespace(response.slice(4)), "base64").toString("latin1");
  } catch {
    throw new Base64DecodeError("Failed to decode response.");
  }
}

/** Login-Daten aus der `userhome(...)`-Seite ziehen (Port von `Login`). */
export function parseUserhome(html: string): { data: unknown; gsecHash: string | null } {
  const inner = html.split("userhome(", 2)[1]?.split(");").slice(0, -1).join(");");
  if (inner === undefined) throw new Error("EduPage did not return login data");
  const cleaned = inner.replace(/[\t\n\r]/g, "");
  let data: unknown;
  try {
    data = JSON.parse(cleaned);
  } catch {
    throw new Error("EduPage did not return login data");
  }
  const gsecHash = html.split('ASC.gsechash="', 2)[1]?.split('"', 1)[0] ?? null;
  return { data, gsecHash: gsecHash ?? null };
}

/** 2FA-Formularfelder (`csrfauth`, `au`, `gu`) aus der Twofactor-Seite ziehen. */
export function extractTwoFactorFields(html: string): { csrf: string; au: string; gu: string } | null {
  try {
    const csrf = html.split('csrfauth" value="', 2)[1]?.split('"', 1)[0];
    const au = html.split('au" value="', 2)[1]?.split('"', 1)[0];
    const gu = html.split('gu" value="', 2)[1]?.split('"', 1)[0];
    if (!csrf || !au || !gu) return null;
    return { csrf, au, gu };
  } catch {
    return null;
  }
}

/** CSRF-Token der Fallback-Loginseite (`"csrftoken":"..."`) ziehen. */
export function extractCsrfToken(html: string): string | null {
  return html.split('"csrftoken":"', 2)[1]?.split('"', 1)[0] ?? null;
}
