import { eventToDict, extractAttachments, fmtLikeDate, likerDisplayName, norm, parseServerDate, prettyTimestamp, recipientsFromDbi, stripHtml, translateServerText, parseLikesResponse } from "./serializers";
import type { TimelineEvent } from "./timeline";

const event = (overrides: Partial<TimelineEvent> = {}): TimelineEvent => ({
  eventId: 7,
  timestamp: new Date(2026, 8, 16, 20, 1, 0),
  text: "Známka aus Mathe",
  author: "Anna Lehrerin",
  recipient: "*",
  eventType: "sprava",
  additionalData: {},
  isDone: false,
  doneAt: null,
  isStarred: false,
  reactionCount: 2,
  createdAt: null,
  isRemoved: false,
  ...overrides,
});

describe("serializers (Parität zu app.py)", () => {
  it("formatiert Zeitstempel deutsch", () => {
    const today = new Date(2026, 8, 20, 12, 0, 0);
    expect(prettyTimestamp(new Date(2026, 8, 20, 10, 0, 0), today)).toBe("Heute · 10:00");
    expect(prettyTimestamp(new Date(2026, 8, 19, 10, 0, 0), today)).toBe("Gestern · 10:00");
    expect(prettyTimestamp(new Date(2026, 8, 16, 20, 1, 0), today)).toBe("Mittwoch · 20:01");
    expect(prettyTimestamp(new Date(2026, 7, 1, 8, 0, 0), today)).toBe("1. August · 08:00");
    expect(prettyTimestamp(new Date(2025, 11, 24, 8, 0, 0), today)).toBe("24. Dezember 2025 · 08:00");
    expect(parseServerDate("2026-09-16 20:01:00")).toEqual(new Date(2026, 8, 16, 20, 1, 0));
  });

  it("baut event_to_dict wie Python", () => {
    const dict = eventToDict(event({ additionalData: { file: "/cloud/a.pdf", name: "Plan" } }), new Date(2026, 8, 20, 12, 0, 0));
    expect(dict).toMatchObject({ id: 7, timestamp: "Mittwoch · 20:01", timestamp_iso: "2026-09-16T20:01:00", sort_key: "2026-09-16T20:01:00", author: "Anna Lehrerin", type: "sprava", type_label: "Nachricht", text: "Note aus Mathe", is_done: false, reaction_count: 2 });
    expect(dict.attachments).toEqual([{ name: "Plan", url: "/cloud/a.pdf" }]);
  });

  it("findet Anhänge generisch und ignoriert Avatare", () => {
    expect(extractAttachments({ avatar: "https://x/y.png", docs: [{ filename: "a.pdf", url: "https://s/a.pdf" }] })).toEqual([{ name: "a.pdf", url: "https://s/a.pdf" }]);
    expect(extractAttachments({ text: 'siehe <a href="/d/b.pdf">hier <b>klicken</b></a>' })).toEqual([{ name: "hier klicken", url: "/d/b.pdf" }]);
    expect(extractAttachments({})).toEqual([]);
  });

  it("schlüsselt Likes/Antworten/Bestätigungen auf", () => {
    const data = { status: "ok", data: { reakcie: [
      { timelineid: "9", typ: "sprava", vlastnik_meno: "Root", data: "{}" },
      { timelineid: "10", typ: "sprava", vlastnik_meno: "Lea Beispiel (Schüler)", data: '{"like":"2026-09-21 09:00:00"}' },
      { timelineid: "11", typ: "sprava", vlastnik_meno: "Max", cas_pridania: "2026-09-21 08:05:00", data: '{"messageContent":"<b>Danke!</b>"}' },
      { timelineid: "12", typ: "confirmation", vlastnik_meno: "Kim", data: "{}" },
    ] } };
    const thread = parseLikesResponse(data, 9);
    expect(thread.likes).toEqual([{ name: "Lea Beispiel", date: "21.09.2026 09:00" }]);
    expect(thread.replies).toEqual([{ name: "Max", date: "21.09.2026 08:05", text: "Danke!" }]);
    expect(thread.summary).toEqual({ total: 3, likes: 1, replies: 1, seen: 1 });
  });

  it("listet Empfänger sortiert ohne Eltern", () => {
    const recs = recipientsFromDbi({ teachers: { 5: { firstname: "Zoe", lastname: "Lehrerin", classroomid: "3" } }, students: { 9: { firstname: "Max", lastname: "A", numberinclass: 4 }, 10: { firstname: "Papa", lastname: "Eltern" } } });
    expect(recs).toEqual([
      { id: "Student9", name: "Max A", kind: "Schüler" },
      { id: "Teacher5", name: "Zoe Lehrerin", kind: "Lehrer" },
    ]);
  });

  it("normt Suche und Namen", () => {
    expect(norm("Müller ÄÖÜ")).toBe("muller aou");
    expect(stripHtml("<p>Hallo &amp; <b>Welt</b></p>")).toBe("Hallo & Welt");
    expect(likerDisplayName("Max Müller (Schüler)")).toBe("Max Müller");
    expect(fmtLikeDate("2026-09-16 20:01:00")).toBe("16.09.2026 20:01");
    expect(translateServerText("Udalosť: Test")).toBe("Ereignis: Test");
  });
});
