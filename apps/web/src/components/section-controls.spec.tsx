/**
 * @jest-environment jsdom
 *
 * `SectionControls` ist die einzige Quelle der Bedienelemente und wird
 * von `section-bar` (Übersicht) und `section-editor` (Einstellungen)
 * benutzt. Geprueft wird die Beschriftung — besonders der Platzhalter
 * `{name}` in `settings.moveUp`/`moveDown`, der einmal unaufgeloest in
 * den aria-labels landete ("Move {name} up").
 */
import { fireEvent, render, screen } from "@testing-library/react";
import { SectionControls, type SectionHints } from "./section-controls";

/** Aus dem echten Katalog, damit die Platzhalter mitwandern. */
const hints = (t: (key: string, vars?: Record<string, string | number>) => string): SectionHints => ({
  drag: t("overview.editorDrag"),
  up: (name: string) => t("settings.moveUp", { name }),
  down: (name: string) => t("settings.moveDown", { name }),
  hide: t("overview.editorHide"),
  show: t("overview.editorShow"),
  hidden: t("overview.editorHidden"),
  wide: t("overview.editorWide"),
  narrow: t("overview.editorNarrow"),
});

/** Ohne Katalog: feste Texte, damit der Test nicht von `i18n` abhaengt. */
const HINTS: SectionHints = {
  drag: "Drag to move",
  up: (name: string) => `Move ${name} up`,
  down: (name: string) => `Move ${name} down`,
  hide: "Hide section",
  show: "Show section",
  hidden: "Hidden",
  wide: "Full width",
  narrow: "Half width",
};

function renderControls(overrides: Partial<Parameters<typeof SectionControls>[0]> = {}) {
  const props = {
    label: "Weather",
    off: false,
    wide: true,
    first: false,
    last: false,
    hints: HINTS,
    onMove: jest.fn(),
    onToggle: jest.fn(),
    onWidth: jest.fn(),
    ...overrides,
  };
  return { ...render(<SectionControls {...props} />), props };
}

describe("SectionControls", () => {
  it("setzt den Abschnittsnamen in jede Beschriftung", () => {
    renderControls();
    expect(screen.getByLabelText("Move Weather up")).toBeTruthy();
    expect(screen.getByLabelText("Move Weather down")).toBeTruthy();
    expect(screen.getByLabelText("Hide section: Weather")).toBeTruthy();
    // wide: true -> der Knopf bietet den Wechsel auf "Half width" an.
    expect(screen.getByLabelText("Half width: Weather")).toBeTruthy();
  });

  it("laesst keine unaufgeloeste Platzhalter stehen", () => {
    renderControls();
    expect(screen.queryByLabelText(/\{name\}/)).toBeNull();
    for (const button of Array.from(document.querySelectorAll("button"))) {
      expect(button.getAttribute("aria-label") ?? "").not.toMatch(/\{[a-z]+\}/);
      expect(button.getAttribute("title") ?? "").not.toMatch(/\{[a-z]+\}/);
    }
  });

  it("bietet beim ausgeblendeten Abschnitt das Einblenden an", () => {
    renderControls({ off: true });
    expect(screen.getByLabelText("Show section: Weather")).toBeTruthy();
    expect(screen.queryByLabelText("Hide section: Weather")).toBeNull();
  });

  it("bietet bei voller Breite das Wechseln an", () => {
    renderControls({ wide: true });
    expect(screen.getByLabelText("Half width: Weather")).toBeTruthy();
  });

  it("bietet bei halber Breite das Wechseln an", () => {
    renderControls({ wide: false });
    expect(screen.getByLabelText("Full width: Weather")).toBeTruthy();
  });

  it("sperrt Hoch am Anfang", () => {
    renderControls({ first: true });
    expect((screen.getByLabelText("Move Weather up") as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByLabelText("Move Weather down") as HTMLButtonElement).disabled).toBe(false);
  });

  it("sperrt Runter am Ende", () => {
    renderControls({ last: true });
    expect((screen.getByLabelText("Move Weather down") as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByLabelText("Move Weather up") as HTMLButtonElement).disabled).toBe(false);
  });

  it("meldet die Richtungen an den Elternteil", () => {
    const { props } = renderControls();
    fireEvent.click(screen.getByLabelText("Move Weather up"));
    fireEvent.click(screen.getByLabelText("Move Weather down"));
    fireEvent.click(screen.getByLabelText("Hide section: Weather"));
    fireEvent.click(screen.getByLabelText("Half width: Weather"));
    expect(props.onMove).toHaveBeenNthCalledWith(1, -1);
    expect(props.onMove).toHaveBeenNthCalledWith(2, 1);
    expect(props.onToggle).toHaveBeenCalledTimes(1);
    expect(props.onWidth).toHaveBeenCalledTimes(1);
  });

  it("zeichnet den Griff nur, wenn Ziehen moeglich ist", () => {
    const { unmount } = renderControls();
    expect(screen.queryByLabelText("Drag to move: Weather")).toBeNull();
    unmount();
    renderControls({ onDragStart: jest.fn() });
    expect(screen.getByLabelText("Drag to move: Weather")).toBeTruthy();
  });
});
