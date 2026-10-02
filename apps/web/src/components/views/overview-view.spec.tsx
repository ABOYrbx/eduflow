/**
 * @jest-environment jsdom
 *
 * Der Layout-Editor der Uebersicht als Ganzes: Reihenfolge aus den
 * Einstellungen, Bearbeitungsmodus, Speichern nach `PUT /settings` und
 * Zuruecksetzen. Deckt die Verbindung aus `section-layout` (Rechenlogik),
 * `SectionBar` (Bedienleiste) und dem Speichern in `overview-view` ab —
 * die Einzelteile haben eigene Tests.
 *
 * `api` ist gemockt: die Ansicht braucht beim Mounten fuenf Aufrufe an den
 * Server, hier zaehlt nur, was mit den Antworten geschieht.
 */
import "../../../test/pointer-event-polyfill";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { OverviewView } from "./overview-view";

const apiMock = jest.fn();
jest.mock("../../lib/api", () => ({ api: (...args: unknown[]) => apiMock(...args) }));

/**
 * Bewusst eine Reihenfolge, die NICHT der Default entspricht: `SECTION_KEYS`
 * ist `[messages, homework, weather]`, gesetzt ist `[weather, messages,
 * homework]`. Sonst waere ein Test, der "Reihenfolge aus Einstellungen"
 * prueft, bei zufaellig gleicher Default-Reihenfolge gruen.
 */
const SETTINGS = {
  schema: [],
  values: { ov_order: "weather,messages,homework", ov_hidden: "", ov_span: "messages:6" },
};

const WEATHER = {
  city: "Berlin",
  today: { temp: 5, max: 9, min: 2, desc: "klar", icon: "01" },
  tomorrow: { max: 9, min: 2, desc: "klar" },
  day3: { max: 9, min: 2, desc: "klar" },
};

/** Standardantworten; `save` steuert das Verhalten von `PUT /settings`. */
function serve(save?: "ok" | "fail") {
  apiMock.mockImplementation((path: string, init?: RequestInit) => {
    if (path.startsWith("/messages")) return Promise.resolve({ items: [], total: 0, limit: 4, offset: 0 });
    if (path.startsWith("/homework")) return Promise.resolve({ items: [], total: 0, limit: 5, offset: 0, counts: {} });
    if (path.startsWith("/timetable")) return Promise.resolve({ lessons: [] });
    if (path.startsWith("/wetter")) return Promise.resolve(WEATHER);
    if (path === "/settings" && init?.method === "PUT") {
      return save === "fail"
        ? Promise.reject(new Error("Server lehnte ab"))
        : Promise.resolve({ values: SETTINGS.values });
    }
    if (path === "/settings") return Promise.resolve(SETTINGS);
    return Promise.resolve({});
  });
}

const puts = () => apiMock.mock.calls.filter(([path, init]) => path === "/settings" && (init as RequestInit)?.method === "PUT");
const lastPutBody = () => JSON.parse((puts().at(-1)?.[1] as RequestInit).body as string);
// Beschriftungen kommen aus messages/en.json (overview.editorToggle / editorHide / editorReset).
const editorToggle = () => screen.getByRole("button", { name: "Arrange" });
const hideWeather = () => screen.getByLabelText("Hide section: Weather");
const resetLayout = () => screen.getByRole("button", { name: /reset/i });

async function mount() {
  render(<OverviewView username="Lea" />);
  // Die Ansicht laedt ihre Daten in einem `Promise.all`; erst danach sind
  // `order` und `spans` aus den Einstellungen gesetzt. Auf den Aufruf von
  // `api` zu warten reicht nicht — der Zustand kommt einen Tick spaeter.
  await waitFor(() => expect(apiMock).toHaveBeenCalledWith("/settings"));
  await act(async () => { await Promise.resolve(); });
  // Das erkennbare Ende: die Wetterkarte ist aus den Daten gebaut.
  await waitFor(() => expect(screen.getByText("Berlin")).toBeTruthy());
}

const slotTexts = () => [...document.querySelectorAll(".ov-slot")].map((slot) => slot.textContent ?? "");

beforeEach(() => {
  apiMock.mockReset();
  serve();
});

describe("OverviewView – Layout-Editor", () => {
  it("rendert die Abschnitte in der Reihenfolge aus den Einstellungen", async () => {
    await mount();
    const texts = slotTexts();
    // gesetzt war ov_order = "weather,messages,homework" — Wetter zuerst,
    // Hausaufgaben zuletzt. Die Default-Reihenfolge waere genau andersherum.
    expect(texts.findIndex((text) => text.includes("Weather"))).toBeLessThan(texts.findIndex((text) => text.includes("Messages")));
    expect(texts.findIndex((text) => text.includes("Messages"))).toBeLessThan(texts.findIndex((text) => text.includes("Homework")));
  });

  it("haengt die halbe Breite aus ov_span an den Abschnitt", async () => {
    await mount();
    const spans = [...document.querySelectorAll(".ov-slot")].map((slot) => (slot as HTMLElement).style.getPropertyValue("--span"));
    // ov_span = "messages:6" -> genau eine halbe, die beiden anderen volle.
    expect(spans.filter((span) => span === "6")).toHaveLength(1);
    expect(spans.filter((span) => span === "12")).toHaveLength(2);
  });

  it("zeigt ohne Bearbeitungsmodus keine Bedienleisten", async () => {
    await mount();
    expect(document.querySelectorAll(".sec-bar")).toHaveLength(0);
  });

  it("zeigt im Bearbeitungsmodus auf jedem Abschnitt eine Bedienleiste", async () => {
    await mount();
    fireEvent.click(editorToggle());
    expect(document.querySelectorAll(".sec-bar")).toHaveLength(3);
  });

  it("haengt einen ausgeblendeten Abschnitt aus, laesst aber seinen Platz im Editor stehen", async () => {
    await mount();
    fireEvent.click(editorToggle());
    fireEvent.click(hideWeather());

    await waitFor(() => expect(puts()).toHaveLength(1));
    // Im Bearbeitungsmodus bleiben alle drei Slots im Raster — sonst waere
    // der ausgeblendete Abschnitt nicht wieder einzuschalten.
    expect(document.querySelectorAll(".ov-slot")).toHaveLength(3);
    const bar = [...document.querySelectorAll(".sec-bar")].find((entry) => entry.textContent?.includes("Weather"));
    expect(bar?.className).toContain("is-off");
    // Die Karte selbst ist weg, nur die Bedienleiste bleibt.
    expect(bar?.querySelector("section")).toBeNull();
    // Und der Knopf bietet jetzt das Einblenden an.
    expect(screen.getByLabelText("Show section: Weather")).toBeTruthy();
  });

  it("haengt einen ausgeblendeten Abschnitt nach dem Verlassen des Editors ganz aus", async () => {
    await mount();
    fireEvent.click(editorToggle());
    fireEvent.click(hideWeather());
    await waitFor(() => expect(puts()).toHaveLength(1));

    fireEvent.click(screen.getByRole("button", { name: "Done" }));
    expect(document.querySelectorAll(".ov-slot")).toHaveLength(2);
  });

  it("speichert Reihenfolge, Ausblendung und Breite als drei Settings", async () => {
    await mount();
    fireEvent.click(editorToggle());
    fireEvent.click(hideWeather());

    await waitFor(() => expect(puts()).toHaveLength(1));
    const body = lastPutBody();
    expect(Object.keys(body).sort()).toEqual(["ov_hidden", "ov_order", "ov_span"]);
    expect(body.ov_hidden).toContain("weather");
    expect(body.ov_order.split(",")).toHaveLength(3);
  });

  it("setzt das Layout auf den Ausgangszustand zurueck", async () => {
    await mount();
    fireEvent.click(editorToggle());
    fireEvent.click(resetLayout());

    await waitFor(() => expect(puts()).toHaveLength(1));
    const body = lastPutBody();
    expect(body.ov_order).toBe("messages,homework,weather");
    expect(body.ov_hidden).toBe("");
    expect(body.ov_span).toBe("");
  });

  it("zeigt einen Fehler, wenn das Speichern scheitert", async () => {
    await mount();
    serve("fail");
    fireEvent.click(editorToggle());
    fireEvent.click(hideWeather());

    await waitFor(() => expect(screen.getByRole("alert").textContent).toContain("Server lehnte ab"));
  });
});
