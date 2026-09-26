import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { HttpException, HttpStatus } from "@nestjs/common";

/** Passwort-Tresor (Paket N-A): AES-256-GCM wie `CredentialVault`.
 *
 * Schlüssel aus `CREDENTIAL_ENCRYPTION_KEY` (64 Hex-Zeichen für 32 Byte,
 * erzeugt per `migration/write-api-config.cjs`; base64 mit 32 Byte geht
 * auch). Fehlt er, gibt es CONFIG_MISSING wie Python.
 */

function keyBytes(): Buffer {
  const raw = (process.env.CREDENTIAL_ENCRYPTION_KEY ?? "").trim().replace(/^["']|["']$/g, "");
  const candidates: Buffer[] = [];
  if (/^[0-9a-fA-F]{64}$/.test(raw)) candidates.push(Buffer.from(raw, "hex"));
  try {
    const urlSafe = raw.replace(/-/g, "+").replace(/_/g, "/");
    const padded = urlSafe + "=".repeat((4 - (urlSafe.length % 4)) % 4);
    if (/^[A-Za-z0-9+/=]+$/.test(raw) && raw.length >= 40) candidates.push(Buffer.from(padded, "base64"));
  } catch {
    /* unten: Längenprüfung */
  }
  const key = candidates.find((candidate) => candidate.length === 32);
  if (!key) {
    throw new HttpException(
      { error: "Server-Schlüssel fehlt. Bitte später erneut versuchen.", code: "CONFIG_MISSING" },
      HttpStatus.SERVICE_UNAVAILABLE,
    );
  }
  return key;
}

export interface SealedPassword { ciphertext: Buffer; nonce: Buffer; }

export function sealPassword(password: string): SealedPassword {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", keyBytes(), nonce);
  const ciphertext = Buffer.concat([cipher.update(password, "utf8"), cipher.final(), cipher.getAuthTag()]);
  return { ciphertext, nonce };
}

export function openPassword(sealed: SealedPassword): string {
  const data = sealed.ciphertext;
  const tag = data.subarray(data.length - 16);
  const body = data.subarray(0, data.length - 16);
  const decipher = createDecipheriv("aes-256-gcm", keyBytes(), sealed.nonce);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
}
