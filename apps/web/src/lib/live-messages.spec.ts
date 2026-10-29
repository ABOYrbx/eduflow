import { clearNewMessages, detectNewMessages, emptyLiveMessages } from "./live-messages";

describe("live-messages", () => {
  it("meldet beim ersten Abruf nichts als neu", () => {
    const next = detectNewMessages(emptyLiveMessages, ["1", "2", "3"]);
    expect(next.count).toBe(0);
    expect([...next.seen]).toEqual(["1", "2", "3"]);
  });

  it("zählt neu eingetroffene Nachrichten", () => {
    const first = detectNewMessages(emptyLiveMessages, ["1", "2"]);
    const second = detectNewMessages(first, ["4", "2", "1"]);
    expect(second.count).toBe(1);
    expect([...second.seen].sort()).toEqual(["1", "2", "4"]);
  });

  it("addiert sich über mehrere Polls, ohne doppelt zu zählen", () => {
    let live = detectNewMessages(emptyLiveMessages, ["1"]);
    live = detectNewMessages(live, ["2"]);
    expect(live.count).toBe(1);
    live = detectNewMessages(live, ["3", "4"]);
    expect(live.count).toBe(3);
    // Derselbe Poll noch einmal darf nichts Neues melden.
    live = detectNewMessages(live, ["3", "4"]);
    expect(live.count).toBe(3);
  });

  it("zählt sofort nach dem Seed durch – ohne Leerlauf-Poll davor", () => {
    // Nutzer-Load seedet: [1,2] sind gesehen. Der naechste Poll darf [3]
    // sofort melden, auch wenn dazwischen kein weiterer Poll lag.
    const seeded = detectNewMessages(emptyLiveMessages, ["1", "2"]);
    expect(seeded.count).toBe(0);
    expect(detectNewMessages(seeded, ["3", "2", "1"]).count).toBe(1);
  });

  it("seedet nach einem Filterwechsel neu, statt den alten Stand zu behalten", () => {
    // Filterwechsel = neuer Seed mit der neuen Liste (leerer Zaehler).
    const first = detectNewMessages(emptyLiveMessages, ["1", "2"]);
    const afterFilterChange = detectNewMessages(emptyLiveMessages, ["9"]);
    expect(afterFilterChange.count).toBe(0);
    // Alles aus der neuen Liste gilt als gesehen, auch was vorher "neu" war.
    expect(detectNewMessages(afterFilterChange, ["9", "10"]).count).toBe(1);
    expect(detectNewMessages(first, ["1"]).count).toBe(0);
  });

  it("behält bekannte IDs, die aus der Liste verschwunden sind", () => {
    const first = detectNewMessages(emptyLiveMessages, ["1", "2"]);
    const second = detectNewMessages(first, ["2"]);
    expect(second.count).toBe(0);
    expect([...second.seen].sort()).toEqual(["1", "2"]);
  });

  it("setzt den Marker zurück, ohne die gesehenen IDs zu verlieren", () => {
    const live = detectNewMessages(detectNewMessages(emptyLiveMessages, ["1"]), ["2"]);
    const cleared = clearNewMessages(live);
    expect(cleared.count).toBe(0);
    expect([...cleared.seen].sort()).toEqual(["1", "2"]);
    // Noch nichts Neues: Rückgabe bleibt identisch (kein unnötiges Re-Render).
    expect(clearNewMessages(cleared)).toBe(cleared);
  });
});