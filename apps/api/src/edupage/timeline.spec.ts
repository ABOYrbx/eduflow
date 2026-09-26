import { fetchTimelineHistory, parseTimelineItems } from "./timeline";
import { MissingDataError, RequestError } from "./errors";
import { EdupageSession, FetchImpl } from "./session";

const ITEMS = [
  { timelineid: "11", typ: "sprava", timestamp: "2026-09-20 10:00:00", text: "Hallo", user_meno: "Max", vlastnik_meno: "Anna", data: '{"messageContent":""}', pocet_reakcii: "3", cas_pridania: "2026-09-20 09:00:00", removed: "0" },
  { timelineid: "12", typ: "sprava", timestamp: "2026-09-19 08:00:00", text: "Dôležitá správa XY", user_meno: "*", vlastnik_meno: "*", data: '{"messageContent":"Wichtig!"}', removed: "0" },
  { timelineid: "", typ: "sprava", timestamp: "2026-09-19 08:00:00", text: "ohne ID", user_meno: "*", vlastnik_meno: "*", data: "{}" },
];

const stubPost = (text: string, status = 200): FetchImpl => async () => ({
  status, url: "https://demo.edupage.org/timeline/", headers: { get: () => null }, text: async () => text, arrayBuffer: async () => new ArrayBuffer(0),
});

describe("parseTimelineItems (Port von __parse_items)", () => {
  it("parst Events, Status und Spezialtexte", () => {
    const events = parseTimelineItems(ITEMS, { "11": { starred: "1", doneMaxCas: "2026-09-21 08:00:00" } });
    expect(events).toHaveLength(2);
    const first = events[0];
    if (!first) throw new Error("kein Event");
    expect(first.eventId).toBe(11);
    expect(first.isStarred).toBe(true);
    expect(first.isDone).toBe(true);
    expect(first.reactionCount).toBe(3);
    expect(first.timestamp).toEqual(new Date(2026, 8, 20, 10, 0, 0));
    const second = events[1];
    if (!second) throw new Error("kein Event");
    expect(second.text).toBe("Wichtig!");
    expect(second.recipient).toBe("*");
  });
});

describe("fetchTimelineHistory (Port von get_notifications_history)", () => {
  it("lädt und parst den Verlauf", async () => {
    const session = new EdupageSession(stubPost(JSON.stringify({ timelineItems: ITEMS, timelineUserProps: {} })));
    const { events } = await fetchTimelineHistory(session, "demo", "2000-01-01");
    expect(events).toHaveLength(2);
  });

  it("meldet Serverfehler und leere Perioden wie Python", async () => {
    await expect(fetchTimelineHistory(new EdupageSession(stubPost("", 500)), "demo", "2000-01-01")).rejects.toBeInstanceOf(RequestError);
    await expect(fetchTimelineHistory(new EdupageSession(stubPost(JSON.stringify({}))), "demo", "2000-01-01")).rejects.toBeInstanceOf(MissingDataError);
  });
});
