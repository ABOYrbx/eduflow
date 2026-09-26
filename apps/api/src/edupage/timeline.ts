import { MissingDataError, RequestError } from "./errors";
import { parseServerDate } from "./serializers";
import { EdupageSession } from "./session";

/** Nachrichtentypen der Nachrichtenliste (Python `MESSAGE_TYPES`, Paket N-B). */
export const MESSAGE_TYPES = ["sprava", "news", "anketa", "chat", "genotif"];

export interface TimelineEvent {
  eventId: number;
  timestamp: Date;
  text: string;
  author: string | null;
  recipient: string | null;
  eventType: string | null;
  additionalData: Record<string, unknown>;
  isDone: boolean;
  doneAt: Date | null;
  isStarred: boolean;
  reactionCount: number;
  createdAt: Date | null;
  isRemoved: boolean;
}

interface RawItem {
  timelineid?: unknown;
  typ?: unknown;
  timestamp?: unknown;
  text?: unknown;
  user_meno?: unknown;
  vlastnik_meno?: unknown;
  data?: unknown;
  cas_pridania?: unknown;
  pocet_reakcii?: unknown;
  removed?: unknown;
}

const asRecord = (value: unknown): Record<string, unknown> => (typeof value === "object" && value !== null && !Array.isArray(value)
  ? value as Record<string, unknown> : {});

/** Timeline-Rohdaten parsen (Port von `TimelineEvents.__parse_items`). */
export function parseTimelineItems(items: unknown, userProps: unknown): TimelineEvent[] {
  if (!Array.isArray(items)) return [];
  const props = asRecord(userProps);
  const out: TimelineEvent[] = [];
  for (const raw of items) {
    const event = raw as RawItem;
    const idRaw = event.timelineid;
    if (idRaw === undefined || idRaw === null || idRaw === "") continue;
    const eventId = Number.parseInt(String(idRaw), 10);
    if (!Number.isInteger(eventId)) continue;
    let eventData: Record<string, unknown> = {};
    try {
      const parsed: unknown = JSON.parse(String(event.data ?? "{}"));
      if (typeof parsed === "object" && parsed !== null) eventData = parsed as Record<string, unknown>;
    } catch {
      eventData = {};
    }
    let text = typeof event.text === "string" ? event.text : "";
    if (text.startsWith("Dôležitá správa")) {
      const content = eventData.messageContent;
      text = typeof content === "string" ? content : "";
    }
    if (text === "") {
      const nazov = eventData.nazov;
      text = typeof nazov === "string" ? nazov : "";
    }
    const recipientName = typeof event.user_meno === "string" ? event.user_meno : null;
    const recipient = recipientName === null ? null : (recipientName === "*" || recipientName === "Celá škola" ? "*" : recipientName);
    const authorName = typeof event.vlastnik_meno === "string" ? event.vlastnik_meno : null;
    const author = authorName === null ? null : (authorName === "*" ? "*" : authorName);
    let additionalData: Record<string, unknown> = {};
    if (typeof event.data === "string") {
      try {
        const parsed: unknown = JSON.parse(event.data);
        if (typeof parsed === "object" && parsed !== null) additionalData = parsed as Record<string, unknown>;
      } catch {
        additionalData = {};
      }
    } else if (typeof event.data === "object" && event.data !== null) {
      additionalData = event.data as Record<string, unknown>;
    }
    const itemProps = asRecord(props[String(idRaw)]);
    const doneRaw = itemProps.doneMaxCas;
    let doneAt: Date | null = null;
    if (typeof doneRaw === "string" && doneRaw) {
      try {
        doneAt = parseServerDate(doneRaw);
      } catch {
        doneAt = null;
      }
    }
    const createdRaw = event.cas_pridania;
    let createdAt: Date | null = null;
    if (typeof createdRaw === "string" && createdRaw) {
      try {
        createdAt = parseServerDate(createdRaw);
      } catch {
        createdAt = null;
      }
    }
    out.push({
      eventId,
      timestamp: parseServerDate(typeof event.timestamp === "string" ? event.timestamp : ""),
      text,
      author,
      recipient,
      eventType: typeof event.typ === "string" ? event.typ : null,
      additionalData,
      isDone: doneAt !== null,
      doneAt,
      isStarred: itemProps.starred === "1",
      reactionCount: Number.parseInt(String(event.pocet_reakcii ?? "0"), 10) || 0,
      createdAt,
      isRemoved: event.removed === "1",
    });
  }
  return out;
}

export interface TimelineFetch { events: TimelineEvent[]; }

/** Verlauf laden (Port von `get_notifications_history`, Paket N-B). */
export async function fetchTimelineHistory(session: EdupageSession, subdomain: string, since: string): Promise<TimelineFetch> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const url = `https://${host}/timeline/?module=todo&filterTab=&akcia=getData&filterTab=messages`;
  const page = await session.postForm(url, { datefrom: since });
  if (page.status !== 200) throw new RequestError(`Edupage returned an error: status=${page.status}`);
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(page.text) as Record<string, unknown>;
  } catch {
    throw new RequestError("Unerwartete Antwort von EduPage.");
  }
  if (!Array.isArray(data.timelineItems)) {
    throw new MissingDataError("Unexpected response from edupage! (no events in this time period?)");
  }
  const userProps = data.timelineUserProps;
  return { events: parseTimelineItems(data.timelineItems, userProps ?? {}) };
}
