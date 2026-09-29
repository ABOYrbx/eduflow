import { RequestError } from "./errors";
import { t } from "../i18n";
import { EdupageSession } from "./session";

/** Hausaufgaben-Flag setzen (Port von `set_homework_done`, Paket N-C). */
export async function setHomeworkDone(session: EdupageSession, subdomain: string, eventId: number | string, done: boolean): Promise<Record<string, unknown>> {
  const host = subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  const page = await session.postEqap(`https://${host}/timeline/?akcia=homeworkFlag`, {
    homeworkid: `timeline:${eventId}`,
    flag: "done",
    value: done ? "1" : "0",
  }, { "X-Requested-With": "XMLHttpRequest" });
  if (page.status !== 200) throw new RequestError(t("upstream.edupageStatus", { status: page.status }));
  let data: Record<string, unknown>;
  try {
    data = JSON.parse(page.text) as Record<string, unknown>;
  } catch {
    throw new RequestError(t("upstream.unexpectedResponse"));
  }
  if (typeof data !== "object" || data === null || !("timelineUserProps" in data)) {
    throw new RequestError(t("upstream.changeUnconfirmed"));
  }
  return data;
}
