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

/** Alles nach dem ERSTEN Vorkommen (Port von `split(sep, 1)[1]`). */
function afterFirst(text: string, sep: string): string | null {
  const index = text.indexOf(sep);
  return index < 0 ? null : text.slice(index + sep.length);
}

/** Login-Daten aus der `userhome(...)`-Seite ziehen (Port von `Login`). */
export function parseUserhome(html: string): { data: unknown; gsecHash: string | null } {
  const after = afterFirst(html, "userhome(");
  if (after === null) throw new Error("EduPage did not return login data");
  // Exakt wie Python `rsplit(");", 2)[0]`: alles außer den letzten zwei Trennern.
  const pieces = after.split(");");
  const inner = (pieces.length <= 2 ? (pieces[0] ?? "") : pieces.slice(0, -2).join(");"))
    .replace(/[\t\n\r]/g, "");
  let data: unknown;
  try {
    data = JSON.parse(inner);
  } catch {
    throw new Error("EduPage did not return login data");
  }
  const gsecPart = afterFirst(html, 'ASC.gsechash="');
  const gsecHash = gsecPart === null ? null : (gsecPart.split('"', 1)[0] ?? null);
  return { data, gsecHash };
}

/** 2FA-Formularfelder (`csrfauth`, `au`, `gu`) aus der Twofactor-Seite ziehen. */
export function extractTwoFactorFields(html: string): { csrf: string; au: string; gu: string } | null {
  try {
    const csrfPart = afterFirst(html, 'csrfauth" value="');
    const auPart = afterFirst(html, 'au" value="');
    const guPart = afterFirst(html, 'gu" value="');
    const csrf = csrfPart?.split('"', 1)[0];
    const au = auPart?.split('"', 1)[0];
    const gu = guPart?.split('"', 1)[0];
    if (!csrf || !au || !gu) return null;
    return { csrf, au, gu };
  } catch {
    return null;
  }
}

/** CSRF-Token der Fallback-Loginseite (`"csrftoken":"..."`) ziehen. */
export function extractCsrfToken(html: string): string | null {
  const part = afterFirst(html, '"csrftoken":"');
  return part?.split('"', 1)[0] ?? null;
}
