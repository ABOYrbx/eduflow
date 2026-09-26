import { fetchThread, replyToMessage, sendTimelineMessage } from "./messages";
import { RequestError } from "./errors";
import { EdupageSession, FetchImpl } from "./session";

function stubFetch(routes: Record<string, { status: number; text: string }>): { fetch: FetchImpl; seen: string[] } {
  const seen: string[] = [];
  const fetch: FetchImpl = async (url, init) => {
    seen.push(`${init.method} ${url} :: ${(init.body ?? "").slice(0, 40)}`);
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url, headers: { get: () => null }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
  return { fetch, seen };
}

const threadUrl = "https://demo.edupage.org/timeline/?akcia=getRepliesItem";
const replyUrl = "https://demo.edupage.org/timeline/?akcia=createReply";
const sendUrl = "https://demo.edupage.org/timeline/?=&akcia=createItem&eqav=1&maxEqav=7";

describe("messages-Protokoll (Port von edupage_api.messages + app.py)", () => {
  it("sendet mit dz-Body und liefert die neue ID", async () => {
    const { fetch, seen } = stubFetch({ [`POST ${sendUrl}`]: { status: 200, text: '{"changes":[{"timelineid":777}]}' } });
    const id = await sendTimelineMessage(new EdupageSession(fetch), "demo", ["Teacher5"], "Hallo");
    expect(id).toBe(777);
    expect(seen[0]).toContain("eqap=dz");
  });

  it("meldet leere changes und 0-Antworten", async () => {
    const zero = stubFetch({ [`POST ${sendUrl}`]: { status: 200, text: "0" } });
    await expect(sendTimelineMessage(new EdupageSession(zero.fetch), "demo", ["Teacher5"], "Hallo")).rejects.toBeInstanceOf(RequestError);
    const empty = stubFetch({ [`POST ${sendUrl}`]: { status: 200, text: '{"changes":[]}' } });
    await expect(sendTimelineMessage(new EdupageSession(empty.fetch), "demo", ["Teacher5"], "Hallo")).rejects.toBeInstanceOf(RequestError);
  });

  it("antwortet per createReply und prüft die Bestätigung", async () => {
    const ok = stubFetch({ [`POST ${replyUrl}`]: { status: 200, text: '{"status":"ok"}' } });
    await expect(replyToMessage(new EdupageSession(ok.fetch), "demo", 7, "Danke")).resolves.toMatchObject({ status: "ok" });
    expect(ok.seen[0]).toContain("eqap=");
    const denied = stubFetch({ [`POST ${replyUrl}`]: { status: 200, text: '{"status":"fail"}' } });
    await expect(replyToMessage(new EdupageSession(denied.fetch), "demo", 7, "Danke")).rejects.toBeInstanceOf(RequestError);
    const broken = stubFetch({ [`POST ${replyUrl}`]: { status: 500, text: "" } });
    await expect(replyToMessage(new EdupageSession(broken.fetch), "demo", 7, "Danke")).rejects.toBeInstanceOf(RequestError);
  });

  it("lädt Threads per getRepliesItem", async () => {
    const ok = stubFetch({ [`POST ${threadUrl}`]: { status: 200, text: '{"status":"ok","data":{"reakcie":[]}}' } });
    const thread = await fetchThread(new EdupageSession(ok.fetch), "demo", 7);
    expect(thread.summary).toEqual({ total: 0, likes: 0, replies: 0, seen: 0 });
    const broken = stubFetch({ [`POST ${threadUrl}`]: { status: 500, text: "" } });
    await expect(fetchThread(new EdupageSession(broken.fetch), "demo", 7)).rejects.toBeInstanceOf(RequestError);
  });
});
