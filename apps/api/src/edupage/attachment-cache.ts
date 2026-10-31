import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import type { DownloadedFile } from "./messages";

/**
 * Server-side attachment cache.
 *
 * EduPage attachments are downloaded by the API, stored on local disk and
 * served to clients from there. This keeps EduPage traffic low and makes
 * repeated downloads (web, Android, macOS) independent of the upstream
 * session.
 */
const DEFAULT_DIR = resolve(process.cwd(), ".cache/attachments");
const DEFAULT_TTL_S = 24 * 60 * 60;

const cacheRoot = (): string =>
  process.env.EDUFLOW_ATTACHMENT_DIR?.trim() || DEFAULT_DIR;

const ttlMs = (): number => {
  const raw = Number.parseInt(process.env.EDUFLOW_ATTACHMENT_TTL_S ?? "", 10);
  return (Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_TTL_S) * 1000;
};

const digest = (value: string): string =>
  createHash("sha256").update(value).digest("hex");

const accountDir = (accountId: string): string =>
  join(cacheRoot(), digest(accountId));

const attachmentDir = (accountId: string, eventId: number, idx: number): string =>
  join(accountDir(accountId), digest(`${accountId}:${eventId}:${idx}`));

interface AttachmentMeta {
  filename: string;
  contentType: string;
  cachedAt: string;
}

export async function readCachedAttachment(
  accountId: string,
  eventId: number,
  idx: number,
): Promise<DownloadedFile | null> {
  const dir = attachmentDir(accountId, eventId, idx);
  try {
    const meta = JSON.parse(await readFile(join(dir, "meta.json"), "utf8")) as AttachmentMeta;
    const cachedAt = Date.parse(meta.cachedAt);
    if (!Number.isFinite(cachedAt) || Date.now() - cachedAt > ttlMs()) return null;
    const bytes = await readFile(join(dir, "data"));
    return {
      filename: meta.filename || "datei",
      contentType: meta.contentType || "application/octet-stream",
      bytes,
    };
  } catch {
    return null;
  }
}

export async function writeCachedAttachment(
  accountId: string,
  eventId: number,
  idx: number,
  file: DownloadedFile,
): Promise<void> {
  const dir = attachmentDir(accountId, eventId, idx);
  await mkdir(dir, { recursive: true });
  const nonce = `${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const dataTmp = join(dir, `data.${nonce}.tmp`);
  const metaTmp = join(dir, `meta.${nonce}.tmp`);
  await writeFile(dataTmp, file.bytes);
  await rename(dataTmp, join(dir, "data"));
  const meta: AttachmentMeta = {
    filename: file.filename,
    contentType: file.contentType,
    cachedAt: new Date().toISOString(),
  };
  await writeFile(metaTmp, JSON.stringify(meta), "utf8");
  await rename(metaTmp, join(dir, "meta.json"));
}

export async function clearAttachmentCache(accountId?: string): Promise<void> {
  try {
    await rm(accountId ? accountDir(accountId) : cacheRoot(), { recursive: true, force: true });
  } catch {
    /* best-effort */
  }
}
