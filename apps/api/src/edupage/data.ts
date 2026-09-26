import { randomBytes } from "node:crypto";
import { BadRequestException, ForbiddenException, HttpException, Injectable, NotFoundException, UnauthorizedException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import type { AuthClaims } from "../auth/auth.service";
import { EdupageClient } from "./client";
import { BadCredentialsError, CaptchaError, MissingDataError } from "./errors";
import { downloadViaSession, fetchThread, replyToMessage, sendTimelineMessage } from "./messages";
import { eventToDict, extractAttachments, norm, recipientsFromDbi } from "./serializers";
import { MESSAGE_TYPES, TimelineEvent, fetchTimelineHistory } from "./timeline";
import { page, parsePage } from "../common/pagination";
import { openPassword } from "./vault";

const TIMELINE_TTL_S = 900;
const LIKES_TTL_S = 3600;
const DL_TTL_S = 300;
const EARLIEST_DEFAULT = "2000-01-01";

const bearerError = (): UnauthorizedException =>
  new UnauthorizedException({ error: "Ungültiges oder fehlendes Token.", code: "TOKEN_INVALID" });

const recipientIdPattern = /^(Teacher|Student|StudentOnly|Parent|Rodic|Ucitel)\d+$/i;

interface StoredEvent {
  eventId: number;
  timestamp: string;
  text: string;
  author: string | null;
  recipient: string | null;
  eventType: string | null;
  additionalData: Record<string, unknown>;
  isDone: boolean;
  doneAt: string | null;
  isStarred: boolean;
  reactionCount: number;
  createdAt: string | null;
  isRemoved: boolean;
}

const storeEvent = (event: TimelineEvent): StoredEvent => ({
  ...event,
  timestamp: event.timestamp.toISOString(),
  doneAt: event.doneAt ? event.doneAt.toISOString() : null,
  createdAt: event.createdAt ? event.createdAt.toISOString() : null,
});

const reviveEvent = (stored: StoredEvent): TimelineEvent => ({
  ...stored,
  timestamp: new Date(stored.timestamp),
  doneAt: stored.doneAt ? new Date(stored.doneAt) : null,
  createdAt: stored.createdAt ? new Date(stored.createdAt) : null,
});

const isoDaysAgo = (days: number): string => {
  const date = new Date(Date.now() - days * 86400000);
  return date.toISOString().slice(0, 10);
};

/** Anmeldefehler für Ressourcen-Pakete (Port von `edupage_login_error`,
 *  N-B-Text für falsche Zugangsdaten wie `api/messages.py`).
 */
export function mapResourceLoginError(error: unknown): HttpException {
  if (error instanceof BadCredentialsError) {
    return new UnauthorizedException({ error: "Benutzername, Passwort oder Subdomain ist falsch.", code: "BAD_CREDENTIALS" });
  }
  if (error instanceof CaptchaError) {
    return new ForbiddenException({ error: "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden.", code: "CAPTCHA_REQUIRED" });
  }
  const detail = error instanceof Error ? error.message : String(error);
  return new HttpException({ error: `Anmeldung fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
}

interface SessionContext {
  client: EdupageClient;
  accountId: string;
  subdomain: string;
  username: string;
  loginData: unknown;
}

/** Echte EduPage-Daten für die Schul-Pakete (N-B; Fake bleibt unberührt). */
@Injectable()
export class EdupageDataService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly clientFactory: () => EdupageClient = () => new EdupageClient(),
  ) {}

  /** EduPage-Re-Login aus Tresor-Zugangsdaten (wie Python `_api_login`). */
  async loginFor(accountId: string): Promise<SessionContext> {
    const account = await this.prisma.userAccount.findUnique({ where: { id: accountId } });
    if (!account) throw bearerError();
    const sealed = await this.prisma.credentialVault.findUnique({ where: { accountId } });
    if (!sealed) throw bearerError();
    let password: string;
    try {
      password = openPassword({ ciphertext: Buffer.from(sealed.ciphertext), nonce: Buffer.from(sealed.nonce) });
    } catch (error) {
      if (error instanceof HttpException) throw error;
      throw bearerError();
    }
    const client = this.clientFactory();
    let result;
    try {
      result = await client.login(account.username, password, account.subdomain);
    } catch (error) {
      throw mapResourceLoginError(error);
    }
    if (result.outcome === "twofactor") {
      throw new UnauthorizedException({ error: "Sitzung erfordert erneut 2FA. Bitte erneut über /auth/login anmelden.", code: "EDUPAGE_2FA" });
    }
    return { client, accountId: account.id, subdomain: result.subdomain, username: account.username, loginData: result.data };
  }

  private async readCache(accountId: string, key: string): Promise<{ payload: Record<string, unknown>; fresh: boolean } | null> {
    const row = await this.prisma.resourceCache.findUnique({ where: { accountId_cacheKey: { accountId, cacheKey: key } } });
    if (!row) return null;
    return { payload: (row.payload ?? {}) as Record<string, unknown>, fresh: row.expiresAt.getTime() > Date.now() };
  }

  private async writeCache(accountId: string, key: string, payload: Record<string, unknown>, ttlS: number): Promise<void> {
    const expiresAt = new Date(Date.now() + ttlS * 1000);
    await this.prisma.resourceCache.upsert({
      where: { accountId_cacheKey: { accountId, cacheKey: key } },
      update: { payload: payload as never, expiresAt },
      create: { accountId, cacheKey: key, payload: payload as never, expiresAt },
    });
  }

  /** Timeline mit Cache (stale/fehlend/`force` → voll neu; beobachtbar wie Python). */
  async timelineEvents(client: EdupageClient, subdomain: string, accountId: string, since: string, force: boolean): Promise<TimelineEvent[]> {
    const cached = await this.readCache(accountId, "timeline");
    if (cached && cached.fresh && !force) {
      const payload = cached.payload as { earliest?: string; events?: StoredEvent[] };
      if (typeof payload.earliest === "string" && payload.earliest <= since && Array.isArray(payload.events)) {
        return payload.events.map(reviveEvent);
      }
    }
    const attempts = [since];
    for (const days of [730, 365]) {
      const fallback = isoDaysAgo(days);
      const last = attempts[attempts.length - 1] ?? since;
      if (fallback > last) attempts.push(fallback);
    }
    let lastError: unknown = null;
    for (const attempt of attempts) {
      try {
        const { events } = await fetchTimelineHistory(client.session, subdomain, attempt);
        await this.writeCache(accountId, "timeline", { earliest: attempt, events: events.map(storeEvent) }, TIMELINE_TTL_S);
        return events;
      } catch (error) {
        if (error instanceof MissingDataError) {
          await this.writeCache(accountId, "timeline", { earliest: attempt, events: [] }, TIMELINE_TTL_S);
          return [];
        }
        lastError = error;
      }
    }
    throw lastError;
  }

  private async resolveEvent(client: EdupageClient, accountId: string, subdomain: string, eventId: number): Promise<TimelineEvent | null> {
    const cached = await this.readCache(accountId, "timeline");
    if (cached) {
      const events = ((cached.payload as { events?: StoredEvent[] }).events ?? []).map(reviveEvent);
      const hit = events.find((event) => event.eventId === eventId);
      if (hit) return hit;
    }
    const fresh = await this.timelineEvents(client, subdomain, accountId, EARLIEST_DEFAULT, true);
    return fresh.find((event) => event.eventId === eventId) ?? null;
  }

  // ---------------------------------------------------------- Liste

  async messages(claims: AuthClaims, query: Record<string, unknown>) {
    const { limit, offset } = parsePage(query);
    const sinceRaw = typeof query.since === "string" && query.since.trim() ? query.since.trim() : EARLIEST_DEFAULT;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(sinceRaw) || Number.isNaN(Date.parse(`${sinceRaw}T00:00:00Z`))) {
      throw new BadRequestException({ error: "Datum muss im Format JJJJ-MM-TT sein.", code: "VALIDATION" });
    }
    const typeFilter = typeof query.type === "string" ? query.type.trim() : "";
    if (typeFilter && !MESSAGE_TYPES.includes(typeFilter)) {
      throw new BadRequestException({ error: `Unbekannter Nachrichtentyp. Gültig: ${[...MESSAGE_TYPES].sort().join(", ")}.`, code: "VALIDATION" });
    }
    const words = norm(typeof query.q === "string" ? query.q.trim().slice(0, 200) : "").split(/\s+/).filter(Boolean);
    const force = query.refresh === "1";
    const { client, subdomain } = await this.loginFor(claims.sub);
    let events: TimelineEvent[];
    try {
      events = await this.timelineEvents(client, subdomain, claims.sub, sinceRaw, force);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Nachrichten konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    const items: Record<string, unknown>[] = [];
    for (const event of events) {
      const type = event.eventType ?? "";
      if (!MESSAGE_TYPES.includes(type) || isReply(event)) continue;
      if (typeFilter && type !== typeFilter) continue;
      const dict = eventToDict(event);
      if (words.length > 0) {
        const hay = norm([dict.author, dict.recipient, dict.text, dict.type_label].map(String).join(" "));
        if (!words.every((word) => hay.includes(word))) continue;
      }
      items.push(dict);
    }
    items.sort((a, b) => {
      const left = String(a.sort_key);
      const right = String(b.sort_key);
      return left < right ? 1 : left > right ? -1 : 0;
    });
    return page(items, { limit: String(limit), offset: String(offset) });
  }

  // ---------------------------------------------------------- Thread

  async thread(claims: AuthClaims, eventId: number, refresh: boolean) {
    if (!Number.isInteger(eventId)) throw new NotFoundException({ error: "Nachricht nicht gefunden.", code: "NOT_FOUND" });
    const key = `likes:${eventId}`;
    const cached = await this.readCache(claims.sub, key);
    if (cached && cached.fresh && !refresh) {
      const payload = cached.payload as { likes?: unknown; replies?: unknown; reply_ids?: unknown; summary?: unknown };
      return { likes: payload.likes ?? [], replies: payload.replies ?? [], reply_ids: payload.reply_ids ?? [], summary: payload.summary ?? {}, cached: true };
    }
    const { client, subdomain } = await this.loginFor(claims.sub);
    let result;
    try {
      result = await fetchThread(client.session, subdomain, eventId);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Thread konnte nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    await this.writeCache(claims.sub, key, { ...result }, LIKES_TTL_S);
    return { ...result, cached: false };
  }

  // ---------------------------------------------------------- Gelesen

  async markRead(claims: AuthClaims) {
    try {
      const cached = await this.readCache(claims.sub, "timeline");
      const stored = ((cached?.payload ?? {}) as { events?: StoredEvent[] }).events ?? [];
      const ids = [...new Set(stored
        .filter((event) => MESSAGE_TYPES.includes(event.eventType ?? ""))
        .map((event) => String(event.eventId)))];
      let marked = 0;
      for (const id of ids) {
        const existing = await this.prisma.localResourceState.findUnique({
          where: { accountId_resource_resourceId_stateKey: { accountId: claims.sub, resource: "timeline", resourceId: id, stateKey: "seen" } },
        });
        if (!existing) {
          await this.prisma.localResourceState.create({
            data: { accountId: claims.sub, resource: "timeline", resourceId: id, stateKey: "seen", value: true },
          });
          marked += 1;
        }
      }
      return { marked };
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Gelesen-Status konnte nicht gespeichert werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
  }

  // ---------------------------------------------------------- Empfänger

  async recipients(claims: AuthClaims, query: Record<string, unknown>) {
    const { limit, offset } = parsePage(query);
    const { loginData } = await this.loginFor(claims.sub);
    let recs;
    try {
      recs = recipientsFromDbi((loginData as Record<string, unknown> | null)?.dbi ?? {});
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Empfänger konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    return page(recs, { limit: String(limit), offset: String(offset) });
  }

  // ---------------------------------------------------------- Senden

  private cleanRecipients(raw: unknown): string[] {
    const list = typeof raw === "string" ? raw.split(",") : Array.isArray(raw) ? raw : [];
    const seen = new Set<string>();
    const valid: string[] = [];
    for (const entry of list) {
      const id = typeof entry === "string" ? entry.trim() : "";
      if (id && !seen.has(id)) {
        seen.add(id);
        if (recipientIdPattern.test(id)) valid.push(id);
      }
    }
    return valid;
  }

  async send(claims: AuthClaims, body: unknown) {
    const input = (typeof body === "object" && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
    const valid = this.cleanRecipients(input.recipients);
    const text = typeof input.body === "string" ? input.body.trim().slice(0, 5000) : "";
    if (!valid.length) throw new BadRequestException({ error: "Bitte mindestens einen gültigen Empfänger angeben.", code: "VALIDATION" });
    if (!text) throw new BadRequestException({ error: "Bitte einen Nachrichtentext eingeben.", code: "VALIDATION" });
    const { client, subdomain } = await this.loginFor(claims.sub);
    let newId: number;
    try {
      newId = await sendTimelineMessage(client.session, subdomain, valid, text);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Senden fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
    }
    try {
      const events = await this.timelineEvents(client, subdomain, claims.sub, EARLIEST_DEFAULT, true);
      const found = events.find((event) => String(event.eventId) === String(newId));
      if (found) return eventToDict(found);
    } catch {
      /* unten: nicht gefunden */
    }
    throw new HttpException({ error: "Gesendet, aber die neue Nachricht wurde nicht gefunden.", code: "UPSTREAM" }, 502);
  }

  // ---------------------------------------------------------- Antworten

  async reply(claims: AuthClaims, eventId: number, body: unknown) {
    const input = (typeof body === "object" && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
    const text = typeof input.body === "string" ? input.body.trim().slice(0, 5000) : "";
    if (!text) throw new BadRequestException({ error: "Bitte einen Antworttext eingeben.", code: "VALIDATION" });
    const { client, subdomain } = await this.loginFor(claims.sub);
    try {
      await replyToMessage(client.session, subdomain, eventId, text);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Antwort fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
    }
    try {
      const result = await fetchThread(client.session, subdomain, eventId);
      await this.writeCache(claims.sub, `likes:${eventId}`, { ...result }, LIKES_TTL_S);
      return { ...result, cached: false };
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Antwort wurde gesendet, der Thread konnte aber nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
  }

  // ---------------------------------------------------------- Downloads

  async downloadToken(claims: AuthClaims, body: unknown) {
    const input = (typeof body === "object" && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
    const eventId = typeof input.event_id === "number" ? input.event_id : Number.NaN;
    const idx = typeof input.idx === "number" ? input.idx : Number.NaN;
    if (!Number.isInteger(eventId) || !Number.isInteger(idx) || (idx as number) < 0) {
      throw new BadRequestException({ error: "Bitte event_id und idx als Zahl angeben.", code: "VALIDATION" });
    }
    const { client, subdomain } = await this.loginFor(claims.sub);
    const event = await this.resolveEvent(client, claims.sub, subdomain, eventId as number);
    if (!event) throw new NotFoundException({ error: "Nachricht nicht gefunden.", code: "NOT_FOUND" });
    this.attachmentUrl(event, subdomain, idx as number);
    const token = randomBytes(18).toString("base64url");
    await this.writeCache(claims.sub, `dl:${token}`, { accountId: claims.sub, eventId: String(eventId), idx: String(idx) }, DL_TTL_S);
    return { download_token: token, expires_in: DL_TTL_S };
  }

  private attachmentUrl(event: TimelineEvent, subdomain: string, idx: number): string {
    const atts = extractAttachments(event.additionalData);
    if (idx < 0 || idx >= atts.length) throw new NotFoundException({ error: "Datei nicht gefunden.", code: "NOT_FOUND" });
    const raw = atts[idx]?.url ?? "";
    const url = raw.startsWith("/") ? `https://${subdomain}.edupage.org${raw}` : raw;
    const host = (() => { try { return new URL(url).hostname; } catch { return ""; } })();
    if (!host.endsWith(".edupage.org")) throw new BadRequestException({ error: "Ungültiger Download-Link.", code: "VALIDATION" });
    return url;
  }

  async attachmentByClaims(claims: AuthClaims, eventId: number, idx: number) {
    const { client, subdomain } = await this.loginFor(claims.sub);
    return this.downloadResolved(client, claims.sub, subdomain, eventId, idx);
  }

  async attachmentByDl(dl: string, eventId: number, idx: number) {
    try {
      await this.prisma.resourceCache.deleteMany({ where: { cacheKey: { startsWith: "dl:" }, expiresAt: { lt: new Date() } } });
    } catch {
      /* best-effort */
    }
    const rows = await this.prisma.resourceCache.findMany({ where: { cacheKey: `dl:${dl}` } });
    const row = rows[0];
    const payload = ((row?.payload ?? {}) as { accountId?: string; eventId?: string; idx?: string });
    if (!row || row.expiresAt.getTime() <= Date.now() || !payload.accountId
      || payload.eventId !== String(eventId) || payload.idx !== String(idx)) {
      throw new UnauthorizedException({ error: "Ungültiges oder fehlendes Token.", code: "TOKEN_INVALID" });
    }
    const { client, subdomain } = await this.loginFor(payload.accountId);
    return this.downloadResolved(client, payload.accountId, subdomain, eventId, idx);
  }

  private async downloadResolved(client: EdupageClient, accountId: string, subdomain: string, eventId: number, idx: number) {
    const event = await this.resolveEvent(client, accountId, subdomain, eventId);
    if (!event) throw new NotFoundException({ error: "Nachricht nicht gefunden.", code: "NOT_FOUND" });
    let url: string;
    try {
      url = this.attachmentUrl(event, subdomain, idx);
    } catch (error) {
      if (error instanceof HttpException) throw error;
      throw new NotFoundException({ error: "Datei nicht gefunden.", code: "NOT_FOUND" });
    }
    try {
      const file = await downloadViaSession(client.session, url, eventIdName(event, idx));
      return file;
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      if (detail.startsWith("EduPage meldet Fehler")) throw new HttpException({ error: detail, code: "UPSTREAM" }, 502);
      throw new HttpException({ error: `Download fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
    }
  }
}

const eventIdName = (event: TimelineEvent, idx: number): string => {
  const atts = extractAttachments(event.additionalData);
  return atts[idx]?.name ?? "datei";
};

const isReply = (event: TimelineEvent): boolean => {
  const data = event.additionalData ?? {};
  return Boolean((data as Record<string, unknown>).textReply);
};

export const __testHelpers = { storeEvent, reviveEvent, isReply };
