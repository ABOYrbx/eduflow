/**
 * @jest-environment jsdom
 *
 * Rauchtests fuer die Ansichten, die beim Zerlegen von
 * `dashboard-app.tsx` verschoben wurden. Sie beantworten eine Frage, die
 * kein Test bisher stellte: Kommt in jeder Ansicht ueberhaupt etwas aus
 * der API im Bild an?
 *
 * Geprueft wird der Weg API-Antwort -> sichtbarer Inhalt, mit den echten
 * Feldnamen aus `lib/types.ts`. Sobald eine Ansicht beim Umbau ein Feld
 * falsch benennt, faellt sie hier auf. Die Details der Logik stehen in
 * `lib/format.ts` (`formatDate`-Specs).
 */
import { act, render, screen, waitFor } from "@testing-library/react";
import { AgendaView } from "./agenda-view";
import { GradesView } from "./grades-view";
import { HomeworkView } from "./homework-view";
import { MessagesView } from "./messages-view";
import { TimetableView } from "./timetable-view";

const apiMock = jest.fn();
jest.mock("../../lib/api", () => ({ api: (...args: unknown[]) => apiMock(...args) }));

const SETTINGS = { schema: [], values: { hw_status: "alle", hw_tests: false } };
const WEATHER = { city: "Berlin", today: { temp: 5, max: 9, min: 2, desc: "klar", icon: "01" }, tomorrow: { max: 9, min: 2, desc: "klar" }, day3: { max: 9, min: 2, desc: "klar" } };

/** Antworten nach Pfad (ohne Query-String), sonst leere Liste. */
const ANSWERS: Record<string, unknown> = {
  "/messages": {
    items: [{ id: 7, text: "Ausflug am Freitag", author: "Frau Berger", recipient: "8A", type: "sprava", type_label: "Message", timestamp: "2026-09-25 14:10", timestamp_iso: "2026-09-25T14:10:00", is_starred: false, reaction_count: 2 }],
    total: 1, limit: 20, offset: 0,
  },
  "/homework": {
    items: [{ id: 3, title: "Arbeitsblatt 4", subject: "Mathe", description: "Bruchrechnung", teacher: "Herr Yilmaz", due: "2026-09-30", due_display: "30.09.", status: "offen", is_done: false, is_hidden: false, type: "homework", type_label: "Homework" }],
    total: 1, limit: 200, offset: 0, counts: { offen: 2, ueberfaellig: 1, erledigt: 5, papierkorb: 0 },
  },
  "/grades": {
    items: [{ id: 11, title: "Klassenarbeit", subject: "Deutsch", teacher: "Frau Klein", date_display: "22.09.2026", date_iso: "2026-09-22", grade_display: "2", grade_num: 2, weight: 1, weight_display: "1x", grade_sub: "", badge: "verygood", class_avg_display: "2,3", comment: "" }],
    total: 1, limit: 200, offset: 0,
  },
  "/school/agenda": {
    items: [{ id: 5, kind: "exam", date: "2026-10-01", title: "Mathetest", subject: "Mathe" }],
  },
  "/substitutions/week": {
    week_label: "KW 40",
    days: [{ date: "2026-09-29", day_label: "Monday", changes: [{ lesson: "3", title: "Vertretungsstunde", action: "change", class: "8A" }] }],
  },
  "/recipients": { items: [{ id: "t1", name: "Frau Berger", kind: "teacher" }], total: 1 },
  // Der Stundenplan startet im Wochenmodus -> `timetable/week`; die
  // Ansicht schaltet aber selbst auf "Tag", dann braucht es beide Formen.
  "/timetable/week": {
    week_label: "KW 40",
    days: [{ date: "2026-09-29", day_name: "Monday", day_date: "29.09.", is_today: false, lessons: [{ period: "1", time: "08:00–08:45", title: "Sport", teachers: "Frau Yilmaz", rooms: "Turnhalle", is_lernzeit: false, is_cancelled: false, is_online: false }] }],
  },
  "/timetable/day": {
    day_label: "Monday",
    lessons: [{ period: "1", time: "08:00–08:45", title: "Sport", teachers: "Frau Yilmaz", rooms: "Turnhalle", is_lernzeit: false, is_cancelled: false, is_online: false }],
  },
};

function serve() {
  apiMock.mockImplementation((path: string) => {
    const route = path.split("?")[0] ?? "";
    const answer = ANSWERS[route];
    if (answer) return Promise.resolve(answer);
    if (path.startsWith("/wetter")) return Promise.resolve(WEATHER);
    if (route === "/settings") return Promise.resolve(SETTINGS);
    return Promise.resolve({ items: [], total: 0, limit: 50, offset: 0 });
  });
}

/** Nach dem Rendern auf die Daten warten. */
async function mount(view: React.ReactElement) {
  render(view);
  await act(async () => { await Promise.resolve(); });
}

beforeEach(() => {
  apiMock.mockReset();
  serve();
});

describe("Rauchtests der Ansichten", () => {
  it("Nachrichten: zeigt Absender und Text der geladenen Nachricht", async () => {
    await mount(<MessagesView />);
    await waitFor(() => expect(screen.getByText("Ausflug am Freitag")).toBeTruthy());
    expect(screen.getByText("Frau Berger")).toBeTruthy();
    // Zwei Reaktionen aus `reaction_count` als eigene Pille.
    expect(screen.getByText("♥ 2")).toBeTruthy();
  });

  it("Hausaufgaben: zeigt Aufgabe und die Zaehler aus `counts`", async () => {
    await mount(<HomeworkView />);
    await waitFor(() => expect(screen.getByText("Arbeitsblatt 4")).toBeTruthy());
    expect(screen.getByText("Herr Yilmaz")).toBeTruthy();
    expect(screen.getByText("Bruchrechnung")).toBeTruthy();
  });

  it("Noten: zeigt Fach, Note und Halbjahr", async () => {
    await mount(<GradesView />);
    await waitFor(() => expect(screen.getByText("Deutsch")).toBeTruthy());
    expect(screen.getByText("Klassenarbeit")).toBeTruthy();
  });

  it("Stundenplan: zeigt Stunde, Raum und Vertretung", async () => {
    await mount(<TimetableView />);
    await waitFor(() => expect(screen.getByText("Sport")).toBeTruthy());
    // Raum und Lehrer stehen gemeinsam in einer Zeile ("Turnhalle · …").
    await waitFor(() => expect(screen.getByText(/Turnhalle/)).toBeTruthy());
    expect(screen.getByText(/Frau Yilmaz/)).toBeTruthy();
    // Die Vertretungswoche kommt aus demselben `SubstitutionList` wie auf
    // der Agenda — sie muss auch hier landen.
    await waitFor(() => expect(screen.getByText("Vertretungsstunde")).toBeTruthy());
  });

  it("Agenda: zeigt Termine und die Vertretungswoche", async () => {
    await mount(<AgendaView />);
    await waitFor(() => expect(screen.getByText("Mathetest")).toBeTruthy());
    await waitFor(() => expect(screen.getByText("Vertretungsstunde")).toBeTruthy());
  });

  it("Verteilt keine kaputten Anteile, wenn eine Antwort fehlt", async () => {
    apiMock.mockImplementation(() => Promise.reject(new Error("Netzwerk weg")));
    await mount(<MessagesView />);
    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("Netzwerk weg"));
    // Die Ansicht stuertzt nicht ab, sondern zeigt den Fehler.
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
  });
});
