import { randomBytes } from "node:crypto";
import { BadRequestException, ForbiddenException, HttpException, Injectable, NotFoundException, Optional, UnauthorizedException } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import type { AuthClaims } from "../auth/auth.service";
import { EdupageClient } from "./client";
import { BadCredentialsError, CaptchaError, MissingDataError } from "./errors";
import { downloadViaSession, fetchThread, replyToMessage, sendTimelineMessage } from "./messages";
import { EXAM_TYPES, HOMEWORK_TYPES, eventToDict, extractAttachments, formatIsoLocal, homeworkRank, homeworkToDict, markHidden, norm, recipientsFromDbi } from "./serializers";
import { MESSAGE_TYPES, TimelineEvent, fetchTimelineHistory } from "./timeline";
import { GERMAN_WEEKDAYS, LessonDict, fetchDayPlan, isAlldayEvent, lessonToDict, mergeLernzeit, parseDayPlan } from "./timetable";
import { changeToDict, fetchSubstitutionHtml, parseSubstitutionHtml, resolveUserClass } from "./school";
import { defaultFetchJson, getWetter, searchWetterCities, type FetchJson } from "./meta";
import { SETTINGS_DEFAULTS, SETTINGS_SCHEMA, coerceSetting, settingsFromForm } from "./settings";
import { fetchGradeData, gradeToDict, parseGrades } from "./grades";
import { setHomeworkDone } from "./homework";
import { page, parsePage } from "../common/pagination";
import { openPassword } from "./vault";

const TIMELINE_TTL_S = 900;
const LIKES_TTL_S = 3600;
const GRADES_TTL_S = 3600;
const DL_TTL_S = 300;
const EARLIEST_DEFAULT = "2000-01-01";

const bearerError = (): UnauthorizedException =>
  new UnauthorizedException({ error: "Ungültiges oder fehlendes Token.", code: "TOKEN_INVALID" });

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

/** Alter lesbar machen (Port von `cache.format_age`). */
export function formatAge(ageS: number | null): string {
  if (ageS === null || ageS === undefined) return "unbekannt";
  if (ageS < 60) return `${ageS} Sek.`;
  const mins = Math.floor(ageS / 60);
  if (mins < 60) return `${mins} Min.`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} Std. ${mins % 60} Min.`;
  return `${Math.floor(hours / 24)} Tage`;
}

/** Flag tolerant lesen (Port von `api/homework._parse_bool`). */
export function parseBoolFlag(value: unknown, fallback = false): boolean {
  if (value === undefined || value === null) return fallback;
  if (typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isInteger(value)) {
    if (value === 0 || value === 1) return value === 1;
    throw new Error("Ungültiger Wahrheitswert (0 oder 1 erwartet).");
  }
  const text = String(value).trim().toLowerCase();
  if (["1", "true", "on", "yes", "ja"].includes(text)) return true;
  if (["0", "false", "off", "no", "nein"].includes(text)) return false;
  throw new Error("Ungültiger Wahrheitswert (true/false erwartet).");
}

/** Anmeldefehler für Ressourcen-Pakete (Port von `edupage_login_error`).
 *
 * Standardtext wie `api/core.py`; nur `api/messages.py` nutzt die
 * N-B-Variante ("Benutzername, ... ist falsch.") per Parameter.
 */
export function mapResourceLoginError(error: unknown, badCredentialsText = "Gespeicherte Zugangsdaten sind ungültig. Bitte erneut anmelden."): HttpException {
  if (error instanceof BadCredentialsError) {
    return new UnauthorizedException({ error: badCredentialsText, code: "BAD_CREDENTIALS" });
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
  gsecHash: string | null;
}

/** Echte EduPage-Daten für die Schul-Pakete (N-B; Fake bleibt unberührt). */
@Injectable()
export class EdupageDataService {
  private readonly fetchJson: FetchJson;
  private readonly clientFactory: () => EdupageClient;

  constructor(
    private readonly prisma: PrismaService,
    @Optional() clientFactory?: () => EdupageClient,
    @Optional() deps?: { fetchJson?: FetchJson },
  ) {
    this.clientFactory = clientFactory ?? (() => new EdupageClient());
    this.fetchJson = deps?.fetchJson ?? defaultFetchJson;
  }

  /** EduPage-Re-Login aus Tresor-Zugangsdaten (wie Python `_api_login`). */
  async loginFor(accountId: string, badCredentialsText?: string): Promise<SessionContext> {
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
      throw mapResourceLoginError(error, badCredentialsText);
    }
    if (result.outcome === "twofactor") {
      throw new UnauthorizedException({ error: "Sitzung erfordert erneut 2FA. Bitte erneut über /auth/login anmelden.", code: "EDUPAGE_2FA" });
    }
    return { client, accountId: account.id, subdomain: result.subdomain, username: account.username, loginData: result.data, gsecHash: result.gsecHash };
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
  async timelineEvents(client: EdupageClient, subdomain: string, accountId: string, since: string, force: boolean): Promise<{ events: TimelineEvent[]; info: string }> {
    const cached = await this.readCache(accountId, "timeline");
    if (cached && cached.fresh && !force) {
      const payload = cached.payload as { earliest?: string; events?: StoredEvent[] };
      if (typeof payload.earliest === "string" && payload.earliest <= since && Array.isArray(payload.events)) {
        return { events: payload.events.map(reviveEvent), info: "aus Cache" };
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
        return { events, info: "frisch geladen" };
      } catch (error) {
        if (error instanceof MissingDataError) {
          await this.writeCache(accountId, "timeline", { earliest: attempt, events: [] }, TIMELINE_TTL_S);
          return { events: [], info: "frisch geladen" };
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
    return fresh.events.find((event) => event.eventId === eventId) ?? null;
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
    const { client, subdomain } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
    let events: TimelineEvent[];
    try {
      ({ events } = await this.timelineEvents(client, subdomain, claims.sub, sinceRaw, force));
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
    const { client, subdomain } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
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
    const { loginData } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
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

  /** Roh-Eingabe normalisieren (trimmen, leere/Dubletten raus), ohne Format-Raten. */
  private normalizeRecipients(raw: unknown): string[] {
    const list = typeof raw === "string" ? raw.split(",") : Array.isArray(raw) ? raw : [];
    const seen = new Set<string>();
    const picked: string[] = [];
    for (const entry of list) {
      const id = typeof entry === "string" ? entry.trim() : "";
      if (id && !seen.has(id)) {
        seen.add(id);
        picked.push(id);
      }
    }
    return picked;
  }

  async send(claims: AuthClaims, body: unknown) {
    const input = (typeof body === "object" && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
    const picked = this.normalizeRecipients(input.recipients);
    const text = typeof input.body === "string" ? input.body.trim().slice(0, 5000) : "";
    if (!picked.length) throw new BadRequestException({ error: "Bitte mindestens einen gültigen Empfänger angeben.", code: "VALIDATION" });
    if (!text) throw new BadRequestException({ error: "Bitte einen Nachrichtentext eingeben.", code: "VALIDATION" });
    const { client, subdomain, loginData } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
    // Nur IDs aus der eigenen Empfängerliste zulassen (Mitgliedschaft statt
    // Format-Raten: dbi-Schlüssel sind nicht überall rein numerisch).
    const known = new Set(recipientsFromDbi((loginData as Record<string, unknown> | null)?.dbi ?? {}).map((item) => item.id));
    const valid = picked.filter((id) => known.has(id));
    if (!valid.length) throw new BadRequestException({ error: "Bitte mindestens einen gültigen Empfänger angeben.", code: "VALIDATION" });
    let newId: number;
    try {
      newId = await sendTimelineMessage(client.session, subdomain, valid, text);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Senden fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
    }
    try {
      const { events } = await this.timelineEvents(client, subdomain, claims.sub, EARLIEST_DEFAULT, true);
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
    const { client, subdomain } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
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
    const { client, subdomain } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
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
    const { client, subdomain } = await this.loginFor(claims.sub, "Benutzername, Passwort oder Subdomain ist falsch.");
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
    const { client, subdomain } = await this.loginFor(payload.accountId, "Benutzername, Passwort oder Subdomain ist falsch.");
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

  // ------------------------------------------------ Hausaufgaben (N-C)

  private async readHwStates(accountId: string, key: string): Promise<Map<string, boolean>> {
    const rows = await this.prisma.localResourceState.findMany({ where: { accountId, resource: "homework", stateKey: key } });
    const out = new Map<string, boolean>();
    for (const row of rows) out.set(String(row.resourceId), row.value === true);
    return out;
  }

  private async writeHwState(accountId: string, id: string | number, key: string, value: boolean): Promise<void> {
    try {
      await this.prisma.localResourceState.upsert({
        where: { accountId_resource_resourceId_stateKey: { accountId, resource: "homework", resourceId: String(id), stateKey: key } },
        update: { value },
        create: { accountId, resource: "homework", resourceId: String(id), stateKey: key, value },
      });
    } catch {
      /* best-effort wie Python */
    }
  }

  private async removeHwState(accountId: string, id: string | number, key: string): Promise<void> {
    try {
      await this.prisma.localResourceState.deleteMany({ where: { accountId, resource: "homework", resourceId: String(id), stateKey: key } });
    } catch {
      /* best-effort wie Python */
    }
  }

  private async buildHomeworkView(
    client: EdupageClient, subdomain: string, accountId: string, username: string,
    since: string, status: string, includeTests: boolean, q: string, force: boolean, today = new Date(),
  ): Promise<{ items: Record<string, unknown>[]; counts: Record<string, number>; cacheInfo: string }> {
    const { events, info } = await this.timelineEvents(client, subdomain, accountId, since, force);
    const wanted = new Set(includeTests ? [...HOMEWORK_TYPES, ...EXAM_TYPES] : HOMEWORK_TYPES);
    const doneState = await this.readHwStates(accountId, "done");
    const trashState = await this.readHwStates(accountId, "trash");
    const dicts: Record<string, unknown>[] = [];
    for (const event of events) {
      if (!wanted.has(event.eventType ?? "")) continue;
      const override = doneState.get(String(event.eventId));
      const effective = override === undefined ? event
        : { ...event, isDone: override, doneAt: override ? (event.doneAt ?? new Date()) : null };
      dicts.push(homeworkToDict(effective, today));
    }
    const hidden = new Set([...trashState.entries()].filter(([, value]) => value).map(([id]) => id));
    const { visible, deleted } = markHidden(dicts, hidden);
    const counts = {
      offen: visible.filter((item) => item.status === "offen" || item.status === "heute fällig").length,
      ueberfaellig: visible.filter((item) => item.status === "überfällig").length,
      erledigt: visible.filter((item) => item.status === "erledigt").length,
      papierkorb: deleted.length,
    };
    let items: Record<string, unknown>[];
    if (status === "papierkorb") items = deleted;
    else if (status === "alle") items = [...visible, ...deleted];
    else items = [...visible];
    if (status === "offen") items = items.filter((item) => item.status === "offen" || item.status === "heute fällig" || item.status === "ohne Datum");
    else if (status === "überfällig") items = items.filter((item) => item.status === "überfällig");
    else if (status === "erledigt") items = items.filter((item) => item.status === "erledigt");
    items.sort((a, b) => {
      const keys = (item: Record<string, unknown>): Array<string | number> =>
        [homeworkRank(item), String(item.due) === "" ? 1 : 0, String(item.due ?? ""), String(item.assigned_iso ?? "")];
      const left = keys(a);
      const right = keys(b);
      for (let index = 0; index < left.length; index += 1) {
        if (left[index] !== right[index]) return (left[index] as string | number) < (right[index] as string | number) ? -1 : 1;
      }
      return 0;
    });
    const needle = q.slice(0, 200).trim().toLowerCase();
    if (needle) {
      items = items.filter((item) => {
        const hay = ["title", "subject", "author", "description", "type_label"]
          .map((key) => String(item[key] ?? "")).join(" ").toLowerCase();
        return hay.includes(needle);
      });
    }
    void username;
    return { items, counts, cacheInfo: info };
  }

  private async homeworkDictById(accountId: string, eventId: number | string, today = new Date()): Promise<Record<string, unknown> | null> {
    const cached = await this.readCache(accountId, "timeline");
    if (!cached) return null;
    const stored = (((cached.payload ?? {}) as { events?: StoredEvent[] }).events ?? []).map(reviveEvent);
    const found = stored.find((event) => String(event.eventId) === String(eventId));
    if (!found) return null;
    try {
      const doneState = await this.readHwStates(accountId, "done");
      const trashState = await this.readHwStates(accountId, "trash");
      const override = doneState.get(String(found.eventId));
      const effective = override === undefined ? found
        : { ...found, isDone: override, doneAt: override ? (found.doneAt ?? new Date()) : null };
      const dict = homeworkToDict(effective, today);
      dict.is_hidden = trashState.get(String(found.eventId)) === true;
      return dict;
    } catch {
      return null;
    }
  }

  async homeworkList(claims: AuthClaims, query: Record<string, unknown>) {
    const { limit, offset } = parsePage(query);
    const sinceRaw = query.since === undefined || query.since === null || String(query.since).trim() === ""
      ? EARLIEST_DEFAULT : String(query.since).trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(sinceRaw) || Number.isNaN(Date.parse(`${sinceRaw}T00:00:00Z`))) {
      throw new BadRequestException({ error: "Ungültiges Datum (YYYY-MM-DD erwartet).", code: "VALIDATION" });
    }
    const status = (typeof query.status === "string" && query.status ? query.status : "alle").trim() || "alle";
    if (!["alle", "offen", "überfällig", "erledigt", "papierkorb"].includes(status)) {
      throw new BadRequestException({ error: "Ungültiger Status (alle, offen, überfällig, erledigt oder papierkorb erwartet).", code: "VALIDATION" });
    }
    let includeTests = false;
    let force = false;
    try {
      includeTests = parseBoolFlag(query.include_tests, false);
      force = parseBoolFlag(query.refresh, false);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new BadRequestException({ error: detail, code: "VALIDATION" });
    }
    const q = typeof query.q === "string" ? query.q : "";
    const { client, subdomain, username } = await this.loginFor(claims.sub);
    let view;
    try {
      view = await this.buildHomeworkView(client, subdomain, claims.sub, username, sinceRaw, status, includeTests, q, force);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Hausaufgaben konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    return { ...page(view.items, { limit: String(limit), offset: String(offset) }), counts: view.counts, cache_info: view.cacheInfo };
  }

  async homeworkDone(claims: AuthClaims, eventId: string, body: unknown, today = new Date()) {
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new BadRequestException({ error: "Ungültige Anfrage (JSON erwartet).", code: "VALIDATION" });
    }
    const input = body as Record<string, unknown>;
    let done: boolean;
    try {
      done = parseBoolFlag(input.done ?? true, true);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new BadRequestException({ error: detail, code: "VALIDATION" });
    }
    const { client, subdomain, username } = await this.loginFor(claims.sub);
    let view;
    try {
      view = await this.buildHomeworkView(client, subdomain, claims.sub, username, EARLIEST_DEFAULT, "alle", true, "", false, today);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Hausaufgaben konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    if (!view.items.some((item) => String(item.id) === String(eventId))) {
      throw new NotFoundException({ error: "Hausaufgabe nicht gefunden.", code: "NOT_FOUND" });
    }
    try {
      await setHomeworkDone(client.session, subdomain, eventId, done);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Status konnte nicht geändert werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    await this.writeHwState(claims.sub, eventId, "done", done);
    const updated = await this.homeworkDictById(claims.sub, eventId, today);
    if (!updated) throw new NotFoundException({ error: "Hausaufgabe nicht gefunden.", code: "NOT_FOUND" });
    return updated;
  }

  async homeworkTrash(claims: AuthClaims, eventId: string, body: unknown, today = new Date()) {
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new BadRequestException({ error: "Ungültige Anfrage (JSON erwartet).", code: "VALIDATION" });
    }
    const input = body as Record<string, unknown>;
    const raw = input.hide ?? input.trash ?? true;
    let hide: boolean;
    try {
      hide = parseBoolFlag(raw, true);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new BadRequestException({ error: detail, code: "VALIDATION" });
    }
    const { client, subdomain, username } = await this.loginFor(claims.sub);
    let view;
    try {
      view = await this.buildHomeworkView(client, subdomain, claims.sub, username, EARLIEST_DEFAULT, "alle", true, "", false, today);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Hausaufgaben konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    const current = view.items.find((item) => String(item.id) === String(eventId));
    if (!current) throw new NotFoundException({ error: "Hausaufgabe nicht gefunden.", code: "NOT_FOUND" });
    if (hide) {
      await this.writeHwState(claims.sub, eventId, "trash", true);
    } else {
      if (HOMEWORK_TYPES.includes(String(current.type ?? ""))) {
        try {
          await setHomeworkDone(client.session, subdomain, eventId, false);
        } catch (error) {
          const detail = error instanceof Error ? error.message : String(error);
          throw new HttpException({ error: `Aufgabe konnte nicht als offen markiert werden: ${detail}`, code: "UPSTREAM" }, 502);
        }
        await this.writeHwState(claims.sub, eventId, "done", false);
      }
      await this.removeHwState(claims.sub, eventId, "trash");
    }
    const updated = await this.homeworkDictById(claims.sub, eventId, today);
    if (!updated) throw new NotFoundException({ error: "Hausaufgabe nicht gefunden.", code: "NOT_FOUND" });
    return updated;
  }

  // ------------------------------------------------ Stundenplan (N-D)

  private timetableTtlFor(dayIso: string, todayIso: string): number {
    if (dayIso < todayIso) return 7 * 24 * 3600;
    if (dayIso === todayIso) return 600;
    return 3600;
  }

  private async loadTimetableDay(client: EdupageClient, accountId: string, subdomain: string, userId: string,
    dbi: unknown, dayIso: string, force: boolean): Promise<{ lessons: LessonDict[]; info: string; fromCache: boolean }> {
    const key = `tt:${dayIso}`;
    const todayIso = new Date().toISOString().slice(0, 10);
    const cached = await this.readCache(accountId, key);
    if (cached && !force) {
      const payload = cached.payload as { lessons?: LessonDict[]; savedAt?: string };
      const ttl = this.timetableTtlFor(dayIso, todayIso);
      const ageS = payload.savedAt ? Math.max(0, Math.round((Date.now() - Date.parse(payload.savedAt)) / 1000)) : Number.MAX_SAFE_INTEGER;
      if (Array.isArray(payload.lessons) && ageS <= ttl) {
        return { lessons: payload.lessons, info: "aus Cache", fromCache: true };
      }
    }
    let plan: unknown[];
    try {
      plan = await fetchDayPlan(client.session, subdomain, userId, dayIso);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Stundenplan konnte nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    const groups = (typeof dbi === "object" && dbi !== null ? dbi : {}) as Record<string, Record<string, { short?: string; firstname?: string; lastname?: string }>>;
    const lessons = parseDayPlan(plan, { subjects: groups.subjects ?? {}, teachers: groups.teachers ?? {}, classrooms: groups.classrooms ?? {} }).map(lessonToDict);
    await this.writeCache(accountId, key, { lessons, savedAt: new Date().toISOString() }, this.timetableTtlFor(dayIso, todayIso));
    return { lessons, info: "frisch geladen", fromCache: false };
  }

  async timetableDay(claims: AuthClaims, query: Record<string, unknown>, today = new Date()) {
    const raw = typeof query.day === "string" ? query.day.trim() : "";
    const dayIso = raw || today.toISOString().slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dayIso) || Number.isNaN(Date.parse(`${dayIso}T00:00:00Z`))) {
      throw new BadRequestException({ error: "Das Datum muss im Format JJJJ-MM-TT angegeben werden.", code: "VALIDATION" });
    }
    const force = query.refresh === "1";
    const { client, subdomain, loginData } = await this.loginFor(claims.sub);
    const userId = String((loginData as Record<string, unknown> | null)?.userid ?? "");
    if (!userId) throw new HttpException({ error: "Stundenplan konnte nicht geladen werden: fehlende Benutzerkennung.", code: "UPSTREAM" }, 502);
    const dbi = (loginData as Record<string, unknown> | null)?.dbi ?? {};
    const loaded = await this.loadTimetableDay(client, claims.sub, subdomain, userId, dbi, dayIso, force);
    const lessons = mergeLernzeit(loaded.lessons);
    const day = new Date(`${dayIso}T00:00:00Z`);
    const pad = (value: number): string => String(value).padStart(2, "0");
    const prev = new Date(day.getTime() - 86400000);
    const next = new Date(day.getTime() + 86400000);
    const iso = (date: Date): string => date.toISOString().slice(0, 10);
    return {
      day: dayIso,
      day_label: `${GERMAN_WEEKDAYS[(day.getUTCDay() + 6) % 7]} ${pad(day.getUTCDate())}.${pad(day.getUTCMonth() + 1)}.${day.getUTCFullYear()}`,
      prev_day: iso(prev),
      next_day: iso(next),
      today: today.toISOString().slice(0, 10),
      lessons,
      cache_info: loaded.info,
    };
  }

  async timetableWeek(claims: AuthClaims, query: Record<string, unknown>, today = new Date()) {
    const raw = typeof query.day === "string" ? query.day.trim() : "";
    const dayIso = raw || today.toISOString().slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dayIso) || Number.isNaN(Date.parse(`${dayIso}T00:00:00Z`))) {
      throw new BadRequestException({ error: "Das Datum muss im Format JJJJ-MM-TT angegeben werden.", code: "VALIDATION" });
    }
    const force = query.refresh === "1";
    const { client, subdomain, loginData } = await this.loginFor(claims.sub);
    const userId = String((loginData as Record<string, unknown> | null)?.userid ?? "");
    if (!userId) throw new HttpException({ error: "Stundenplan konnte nicht geladen werden: fehlende Benutzerkennung.", code: "UPSTREAM" }, 502);
    const dbi = (loginData as Record<string, unknown> | null)?.dbi ?? {};
    const base = new Date(`${dayIso}T00:00:00Z`);
    const monday = new Date(base.getTime() - (((base.getUTCDay() + 6) % 7) * 86400000));
    const iso = (date: Date): string => date.toISOString().slice(0, 10);
    const pad = (value: number): string => String(value).padStart(2, "0");
    const days: Record<string, unknown>[] = [];
    let cachedCount = 0;
    for (let index = 0; index < 5; index += 1) {
      const current = new Date(monday.getTime() + index * 86400000);
      const currentIso = iso(current);
      const loaded = await this.loadTimetableDay(client, claims.sub, subdomain, userId, dbi, currentIso, force);
      if (loaded.fromCache) cachedCount += 1;
      days.push({
        date: currentIso,
        day_name: GERMAN_WEEKDAYS[(current.getUTCDay() + 6) % 7],
        day_date: `${pad(current.getUTCDate())}.${pad(current.getUTCMonth() + 1)}.`,
        is_today: currentIso === today.toISOString().slice(0, 10),
        lessons: mergeLernzeit(loaded.lessons).filter((entry) => !isAlldayEvent(entry)),
      });
    }
    const friday = new Date(monday.getTime() + 4 * 86400000);
    const cacheInfo = cachedCount === 5 ? "Woche aus Cache (0 API-Requests)"
      : cachedCount > 0 ? `Woche teils aus Cache (${cachedCount}/5 Tage, ${5 - cachedCount} neu geladen)`
        : "Woche frisch geladen (5 API-Requests)";
    return {
      day: dayIso,
      monday: iso(monday),
      week_label: `Woche ${pad(monday.getUTCDate())}.${pad(monday.getUTCMonth() + 1)}. – ${pad(friday.getUTCDate())}.${pad(friday.getUTCMonth() + 1)}.${friday.getUTCFullYear()}`,
      days,
      cache_info: cacheInfo,
    };
  }

  // ------------------------------------------------ Noten (N-E)

  async gradesList(claims: AuthClaims, query: Record<string, unknown>) {
    const { limit, offset } = parsePage(query);
    const force = query.refresh === "1";
    if (!force) {
      const cached = await this.readCache(claims.sub, "grades");
      if (cached && cached.fresh) {
        const payload = cached.payload as { grades?: Record<string, unknown>[]; savedAt?: string };
        if (Array.isArray(payload.grades)) {
          const age = payload.savedAt ? Math.max(0, Math.round((Date.now() - Date.parse(payload.savedAt)) / 1000)) : 0;
          return { ...page(payload.grades, { limit: String(limit), offset: String(offset) }), cache_info: `aus Cache (${formatAge(age)} alt)` };
        }
      }
    }
    const { client, subdomain, loginData } = await this.loginFor(claims.sub);
    let dicts: Record<string, unknown>[];
    try {
      const data = await fetchGradeData(client.session, subdomain);
      const dbi = ((loginData as Record<string, unknown> | null)?.dbi ?? {}) as { subjects?: Record<string, { short?: string }>; teachers?: Record<string, { firstname?: string; lastname?: string }> };
      dicts = parseGrades(data, dbi).map(gradeToDict);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Noten konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    await this.writeCache(claims.sub, "grades", { grades: dicts, savedAt: new Date().toISOString() }, GRADES_TTL_S);
    return { ...page(dicts, { limit: String(limit), offset: String(offset) }), cache_info: "frisch geladen" };
  }

  // ---------------------------------------------------------- Wetter (N-G)

  /** Wetter-Proxy (Port von `api_wetter`). */
  async weather(query: Record<string, unknown>) {
    const coord = (value: unknown): number | null => {
      if (typeof value !== "string" || !value.trim()) return null;
      const num = Number(value);
      return Number.isFinite(num) ? num : null;
    };
    const lat = coord(query.lat);
    const lon = coord(query.lon);
    const city = (typeof query.city === "string" ? query.city : "").trim().slice(0, 100);
    if ((lat === null || lon === null) && !city) {
      throw new BadRequestException({ error: "Bitte Koordinaten (?lat=..&lon=..) oder Stadt (?city=..) angeben.", code: "VALIDATION" });
    }
    const key = process.env.OPENWEATHER_KEY ?? "";
    const { payload, status } = await getWetter(this.fetchJson, key, lat, lon, city);
    if (status === 200) return payload;
    const message = typeof payload.error === "string" ? payload.error : "Wetter derzeit nicht verfügbar.";
    if (status === 400) throw new BadRequestException({ error: message, code: "VALIDATION" });
    if (status === 503) throw new HttpException({ error: message, code: "CONFIG_MISSING" }, 503);
    throw new HttpException({ error: message, code: "UPSTREAM" }, 502);
  }

  /** Wetter-Ortssuche (Port von `api_wetter_suche`). */
  async searchCities(query: unknown) {
    const text = (typeof query === "string" ? query : "").trim().slice(0, 100);
    const key = process.env.OPENWEATHER_KEY ?? "";
    const { payload, status } = await searchWetterCities(this.fetchJson, key, text);
    if (status === 200) return payload;
    const message = typeof payload.error === "string" ? payload.error : "Stadtsuche nicht verfügbar.";
    if (status === 503) throw new HttpException({ error: message, code: "CONFIG_MISSING" }, 503);
    throw new HttpException({ error: message, code: "UPSTREAM" }, 502);
  }

  // ------------------------------------------ Schulalltag (N-H)

  async substitutionsWeek(claims: AuthClaims, query: Record<string, unknown>, today = new Date()) {
    const raw = typeof query.day === "string" ? query.day.trim() : "";
    const selected = raw || today.toISOString().slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(selected) || Number.isNaN(Date.parse(`${selected}T00:00:00Z`))) {
      throw new BadRequestException({ error: "Das Datum muss im Format JJJJ-MM-TT angegeben werden.", code: "VALIDATION" });
    }
    const { client, subdomain, loginData, gsecHash } = await this.loginFor(claims.sub);
    const base = new Date(`${selected}T00:00:00Z`);
    const monday = new Date(base.getTime() - (((base.getUTCDay() + 6) % 7) * 86400000));
    const iso = (date: Date): string => date.toISOString().slice(0, 10);
    const pad = (value: number): string => String(value).padStart(2, "0");
    const userClass = resolveUserClass((loginData as Record<string, unknown> | null)?.dbi ?? {},
      (loginData as Record<string, unknown> | null)?.userid ?? "");
    const days: Record<string, unknown>[] = [];
    try {
      for (let index = 0; index < 5; index += 1) {
        const current = new Date(monday.getTime() + index * 86400000);
        const currentIso = iso(current);
        const html = await fetchSubstitutionHtml(client.session, subdomain, gsecHash ?? "", currentIso);
        const changes = parseSubstitutionHtml(html) ?? [];
        const filtered = userClass ? changes.filter((change) => change.changeClass === userClass) : changes;
        days.push({
          date: currentIso,
          day_label: `${GERMAN_WEEKDAYS[(current.getUTCDay() + 6) % 7]} ${pad(current.getUTCDate())}.${pad(current.getUTCMonth() + 1)}.${current.getUTCFullYear()}`,
          changes: filtered.map(changeToDict),
        });
      }
    } catch {
      throw new HttpException({ error: "Vertretungsplan konnte nicht geladen werden.", code: "UPSTREAM" }, 502);
    }
    const friday = new Date(monday.getTime() + 4 * 86400000);
    return {
      monday: iso(monday),
      week_label: `Woche ${pad(monday.getUTCDate())}.${pad(monday.getUTCMonth() + 1)}. – ${pad(friday.getUTCDate())}.${pad(friday.getUTCMonth() + 1)}.${friday.getUTCFullYear()}`,
      days,
    };
  }

  async agenda(claims: AuthClaims, query: Record<string, unknown>, today = new Date()) {
    const parseRangeDate = (value: unknown, fallback: string): string => {
      const text = typeof value === "string" && value.trim() ? value.trim() : fallback;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(text) || Number.isNaN(Date.parse(`${text}T00:00:00Z`))) {
        throw new BadRequestException({ error: "Das Datum muss im Format JJJJ-MM-TT angegeben werden.", code: "VALIDATION" });
      }
      return text;
    };
    const shiftIso = (days: number): string => new Date(today.getTime() + days * 86400000).toISOString().slice(0, 10);
    const since = parseRangeDate(query.since, shiftIso(-30));
    const until = parseRangeDate(query.until, shiftIso(60));
    const spanDays = Math.round((Date.parse(`${until}T00:00:00Z`) - Date.parse(`${since}T00:00:00Z`)) / 86400000);
    if (until < since || spanDays > 366) {
      throw new BadRequestException({ error: "Der Zeitraum darf höchstens ein Jahr umfassen.", code: "VALIDATION" });
    }
    const force = query.refresh === "1";
    const { client, subdomain } = await this.loginFor(claims.sub);
    let events: TimelineEvent[];
    let info: string;
    try {
      ({ events, info } = await this.timelineEvents(client, subdomain, claims.sub, since, force));
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Schultermine konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    let items: Record<string, unknown>[];
    try {
      items = this.buildAgendaItems(events, since, until, today);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Schultermine konnten nicht geladen werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    return { items, total: items.length, since, until, cache_info: info };
  }

  private buildAgendaItems(events: TimelineEvent[], since: string, until: string, today: Date): Record<string, unknown>[] {
    const calendar = new Set(["ctevent", "bmeeting", "culture", "event", "excursion", "parentsevening", "schoolevent", "trip", "meeting", "freeday", "holiday", "sholiday", "project"]);
    const attendance = new Set(["student_absent", "ospravedlnenka", "h_attendance", "pipnutie"]);
    const items: Record<string, unknown>[] = [];
    for (const event of events) {
      const type = event.eventType ?? "";
      const inCalendar = calendar.has(type);
      const inAttendance = attendance.has(type);
      const inExams = EXAM_TYPES.includes(type);
      if (!inCalendar && !inAttendance && !inExams) continue;
      const kind = inAttendance ? "attendance" : inExams ? "exam" : "event";
      const item = kind === "exam" ? homeworkToDict(event, today) : eventToDict(event, today);
      let eventDay = formatIsoLocal(event.timestamp).slice(0, 10);
      if (kind === "exam" && typeof item.due === "string" && item.due) {
        if (/^\d{4}-\d{2}-\d{2}$/.test(item.due) && !Number.isNaN(Date.parse(`${item.due}T00:00:00Z`))) eventDay = item.due;
      }
      if (eventDay < since || eventDay > until) continue;
      item.kind = kind;
      item.date = eventDay;
      items.push(item);
    }
    const titleOf = (item: Record<string, unknown>): string => String(item.title ?? item.text ?? "").toLowerCase();
    const isoOf = (item: Record<string, unknown>): string => String(item.timestamp_iso ?? item.assigned_iso ?? "");
    items.sort((a, b) => {
      const keysA = [String(a.date), isoOf(a), titleOf(a)];
      const keysB = [String(b.date), isoOf(b), titleOf(b)];
      for (let index = 0; index < keysA.length; index += 1) {
        if (keysA[index] !== keysB[index]) return (keysA[index] as string) < (keysB[index] as string) ? -1 : 1;
      }
      return 0;
    });
    return items;
  }

  // --------------------------------------- Einstellungen + Cache (N-F)

  async settingsGet(claims: AuthClaims) {
    const merged: Record<string, unknown> = { ...SETTINGS_DEFAULTS };
    try {
      const rows = await this.prisma.userPreference.findMany({ where: { accountId: claims.sub } });
      const stored: Record<string, unknown> = {};
      for (const row of rows) stored[row.key] = row.value;
      for (const spec of SETTINGS_SCHEMA) {
        if (spec.key in stored) merged[spec.key] = coerceSetting(spec, stored[spec.key]);
      }
    } catch {
      /* Defaults wie Python */
    }
    return { schema: SETTINGS_SCHEMA, values: merged };
  }

  async settingsPut(claims: AuthClaims, body: unknown) {
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new BadRequestException({ error: "Ungültige Anfrage (JSON-Objekt erwartet).", code: "VALIDATION" });
    }
    const current = await this.settingsGet(claims);
    const input = { ...(current.values as Record<string, unknown>), ...(body as Record<string, unknown>) };
    const normalized: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(input)) {
      if (value === true) normalized[key] = "1";
      else if (value === false) normalized[key] = "0";
      else normalized[key] = value;
    }
    let values: Record<string, unknown>;
    try {
      values = settingsFromForm(normalized);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new BadRequestException({ error: `Einstellungen konnten nicht gespeichert werden: ${detail}`, code: "VALIDATION" });
    }
    try {
      for (const spec of SETTINGS_SCHEMA) {
        await this.prisma.userPreference.upsert({
          where: { accountId_key: { accountId: claims.sub, key: spec.key } },
          update: { value: values[spec.key] as never },
          create: { accountId: claims.sub, key: spec.key, value: values[spec.key] as never },
        });
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Einstellungen konnten nicht gespeichert werden: ${detail}`, code: "UPSTREAM" }, 502);
    }
    return { status: "ok", values: (await this.settingsGet(claims)).values };
  }

  async cacheClear(claims: AuthClaims) {
    try {
      const result = await this.prisma.resourceCache.deleteMany({ where: { accountId: claims.sub } });
      return { status: "ok", cleared: result.count };
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new HttpException({ error: `Cache konnte nicht gelöscht werden: ${detail}`, code: "UPSTREAM" }, 502);
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
