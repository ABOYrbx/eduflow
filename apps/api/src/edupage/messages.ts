import { decodeResponse, encodeRequestBody } from "./protocol";
import { parseLikesResponse } from "./serializers";
import { RequestError } from "./errors";
import { t } from "../i18n";
import { EdupageSession } from "./session";

/** Nachrichten-Protokoll (Port von `edupage_api.messages` + `app.py`, N-B). */

export async function sendTimelineMessage(session: EdupageSession, subdomain: string, recipients: string[], body: string): Promise<number> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const payload = encodeRequestBody({ selectedUser: recipients.join(";"), text: body, attachements: "{}", receipt: "0", typ: "sprava" });
  const page = await session.postRaw(`https://${host}/timeline/?=&akcia=createItem&eqav=1&maxEqav=7`, payload);
  const text = decodeResponse(page.text);
  if (text === "0") throw new RequestError("Edupage returned an error response");
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(text) as Record<string, unknown>;
  } catch {
    throw new RequestError(t("upstream.unexpectedResponse"));
  }
  const changes = data.changes;
  if (!Array.isArray(changes) || changes.length === 0) {
    throw new RequestError("Failed to send message (edupage returned an empty 'changes' array)");
  }
  const first = changes[0] as Record<string, unknown>;
  const id = Number.parseInt(String(first.timelineid ?? ""), 10);
  if (!Number.isInteger(id)) throw new RequestError("Failed to send message (missing timelineid)");
  return id;
}

const XML_REQUESTED_WITH = { "X-Requested-With": "XMLHttpRequest" };

export async function replyToMessage(session: EdupageSession, subdomain: string, groupId: number | string, text: string): Promise<Record<string, unknown>> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const page = await session.postEqap(`https://${host}/timeline/?akcia=createReply`, {
    groupid: String(groupId),
    recipient: "",
    text,
    moredata: JSON.stringify({ attachements: {} }),
  }, XML_REQUESTED_WITH);
  if (page.status !== 200) throw new RequestError(t("upstream.edupageStatus", { status: page.status }));
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(page.text) as Record<string, unknown>;
  } catch {
    throw new RequestError(t("upstream.unexpectedResponse"));
  }
  if (typeof data !== "object" || data === null || String(data.status ?? "").toLowerCase() !== "ok") {
    throw new RequestError(t("upstream.replyUnconfirmed"));
  }
  return data;
}

export async function fetchThread(session: EdupageSession, subdomain: string, eventId: number | string): Promise<ReturnType<typeof parseLikesResponse>> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const page = await session.postEqap(`https://${host}/timeline/?akcia=getRepliesItem`, { groupid: String(eventId), lastsync: "" }, XML_REQUESTED_WITH);
  if (page.status !== 200) throw new RequestError(t("upstream.edupageStatus", { status: page.status }));
  let data: unknown;
  try {
    data = JSON.parse(page.text) as unknown;
  } catch {
    throw new RequestError(t("upstream.unexpectedResponse"));
  }
  return parseLikesResponse(data, eventId);
}

export interface DownloadedFile { filename: string; contentType: string; bytes: Buffer; }

/** Anhang laden (Session-Proxy wie Python `message_attachment`). */
export async function downloadViaSession(session: EdupageSession, url: string, fallbackName: string): Promise<DownloadedFile> {
  const fetched = await session.getBytes(url);
  if (fetched.status !== 200) throw new RequestError(t("upstream.edupageStatus", { status: fetched.status }));
  const clean = fallbackName.replace(/["\r\n]/g, "").trim().slice(0, 120) || "datei";
  const contentType = fetched.contentType.split(";")[0]?.trim() || "application/octet-stream";
  return { filename: clean, contentType, bytes: fetched.bytes };
}
