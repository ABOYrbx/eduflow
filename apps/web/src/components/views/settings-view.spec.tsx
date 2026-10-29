/**
 * @jest-environment jsdom
 *
 * Das Einstellungsformular ist schema-getrieben: es rendert fuer jeden
 * Eintrag aus `settings.schema` ein Feld. Das Schema des Backends kennt
 * `bool`, `select`, `int`, `order`, `hidden`, `span` und `text`.
 *
 * Hier geprueft wird der generic-Lesepfad in `save()` — er laeuft ueber
 * `form.get(item.key)`, also gewinnt bei mehreren Feldern mit
 * demselben `name` das letzte im DOM. Genau daran ist `ov_span`
 * gescheitert: es gibt ein verstecktes Input aus dem Abschnitts-Editor
 * UND (ueber den generischen else-Zweig) ein sichtbares fuer `span`.
 */
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { SettingsView } from "./settings-view";

const apiMock = jest.fn();
jest.mock("../../lib/api", () => ({ api: (...args: unknown[]) => apiMock(...args) }));

/** Schema genau wie es die API liefert — alle sieben Arten. */
const SCHEMA = [
  { key: "hw_status", kind: "select", label: "Homework: Standard filter", options: [["alle", "All"], ["offen", "Only open"]], default: "alle" },
  { key: "ov_unread", kind: "int", label: "Overview: max. unread messages", min: 1, max: 50, default: 10 },
  { key: "hw_tests", kind: "bool", label: "Homework: Include tests by default", default: false },
  { key: "ov_order", kind: "order", section: "Overview", label: "Overview section order", default: "messages,homework,weather" },
  { key: "ov_hidden", kind: "hidden", section: "Overview", label: "Hidden sections", default: "" },
  { key: "ov_span", kind: "span", section: "Overview", label: "Section widths", default: "" },
  { key: "wetter_city", kind: "text", label: "Weather: City", placeholder: "e.g. Berlin", default: "" },
];

const VALUES = {
  hw_status: "offen", ov_unread: 10, hw_tests: false,
  ov_order: "weather,messages,homework", ov_hidden: "weather", ov_span: "messages:6",
  wetter_city: "Berlin",
};

function serve() {
  apiMock.mockImplementation((path: string, init?: RequestInit) => {
    if (path === "/devices") return Promise.resolve({ items: [] });
    if (path === "/settings" && init?.method === "PUT") return Promise.resolve({ values: VALUES });
    if (path === "/settings") return Promise.resolve({ schema: SCHEMA, values: VALUES });
    return Promise.resolve({});
  });
}

const putBody = (): Record<string, unknown> => {
  const puts = apiMock.mock.calls.filter((call) => call[0] === "/settings" && (call[1] as RequestInit)?.method === "PUT");
  const call = puts[puts.length - 1];
  return JSON.parse((call?.[1] as RequestInit).body as string) as Record<string, unknown>;
};

async function mount() {
  render(<SettingsView />);
  await waitFor(() => expect(screen.getByRole("button", { name: /^save|save|sp/i })).toBeTruthy());
  await act(async () => { await Promise.resolve(); });
}

beforeEach(() => {
  apiMock.mockReset();
  serve();
});

describe("SettingsView – schema-getriebenes Formular", () => {
  it("laedt das Schema und fuellt die Werte", async () => {
    await mount();
    expect(screen.getByLabelText("Weather: City")).toBeTruthy();
    expect((screen.getByLabelText("Weather: City") as HTMLInputElement).value).toBe("Berlin");
  });

  it("rendert fuer jede behandelte Art ein Feld", async () => {
    await mount();
    expect(screen.getByLabelText("Overview: max. unread messages")).toBeTruthy();  // int
    expect(screen.getByText("Homework: Include tests by default")).toBeTruthy();   // bool
    expect(screen.getByText("Overview section order")).toBeTruthy();               // order
  });

  it("legt die Layout-Einstellungen als versteckte Felder an", async () => {
    await mount();
    const hidden = (name: string) => document.querySelector(`input[type="hidden"][name="${name}"]`) as HTMLInputElement;
    expect(hidden("ov_order").value).toBe("weather,messages,homework");
    expect(hidden("ov_hidden").value).toBe("weather");
    expect(hidden("ov_span").value).toBe("messages:6");
  });

  it("haelt den Abschnitts-Editor und das generische Feld fuer ov_span auseinander", async () => {
    await mount();
    // Zwei Felder mit demselben `name` wuerden beim Speichern kollidieren:
    // `form.get` gewinnt das letzte im DOM.
    const spanFields = document.querySelectorAll('input[name="ov_span"]');
    expect(spanFields).toHaveLength(1);
  });

  it("schickt beim Speichern genau die Layout-Werte des Editors mit", async () => {
    await mount();
    fireEvent.click(screen.getByRole("button", { name: /save/i }));
    await waitFor(() => expect(putBody()).toBeTruthy());
    const body = putBody();
    expect(body.ov_order).toBe("weather,messages,homework");
    expect(body.ov_hidden).toBe("weather");
    expect(body.ov_span).toBe("messages:6");
  });

  it("rendert den Abschnitts-Editor bedienbar", async () => {
    await mount();
    // Die Knoepfe des Editors (hoch/runter, Breite, ausblenden) muessen
    // das Layout aendern — sonst waere die Reihenfolge in den
    // Einstellungen nur scheinbar bedienbar.
    expect(screen.getByLabelText(/move messages down/i)).toBeTruthy();
    fireEvent.click(screen.getByLabelText(/move messages down/i));
    await act(async () => { await Promise.resolve(); });
    const hiddenOrder = document.querySelector('input[type="hidden"][name="ov_order"]') as HTMLInputElement;
    // gesetzt war "weather,messages,homework" -> messages rutscht hinter weather.
    expect(hiddenOrder.value).toBe("weather,homework,messages");
  });

  it("schickt int-Werte als Zahl, bool als Anwesenheit und Text als String", async () => {
    await mount();
    fireEvent.change(screen.getByLabelText("Overview: max. unread messages"), { target: { value: "25" } });
    fireEvent.click(screen.getByText("Homework: Include tests by default"));
    fireEvent.click(screen.getByRole("button", { name: /save/i }));

    await waitFor(() => expect(putBody()).toBeTruthy());
    const body = putBody();
    expect(body.ov_unread).toBe(25);
    expect(body.hw_tests).toBe(true);
    expect(body.wetter_city).toBe("Berlin");
    expect(typeof body.ov_unread).toBe("number");
    expect(typeof body.wetter_city).toBe("string");
  });
});
