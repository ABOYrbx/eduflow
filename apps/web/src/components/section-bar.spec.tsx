/**
 * @jest-environment jsdom
 *
 * Verhalten der Bedienleiste auf den Karten der Übersicht. Die reine
 * Rechenlogik (`hitIndexByMidline`, `moveItem`) ist in
 * `lib/section-layout.spec.ts` abgedeckt; hier geht es um das Drum und
 * Dran im Browser: Ziehen per Zeiger, die Klassen während des Zugs und
 * die vier Knöpfe.
 *
 * `measure` wird vom Elternteil geliefert und hier simuliert: drei Karten
 * à 100 px, die Mittellinie liegt damit bei 50/150/250.
 */
import "../../test/pointer-event-polyfill";
import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { SectionBar } from "./section-bar";
import { SECTION_KEYS, type SectionState } from "../lib/section-layout";

const HINTS = {
  drag: "Ziehen",
  up: (name: string) => `Hoch: ${name}`,
  down: (name: string) => `Runter: ${name}`,
  hide: "Ausblenden", show: "Einblenden", hidden: "ausgeblendet",
  wide: "Breit", narrow: "Schmal",
};
const RECTS = [{ top: 0, bottom: 100 }, { top: 100, bottom: 200 }, { top: 200, bottom: 300 }];
const measure = () => RECTS;

/** Hält den Zustand, damit die Karte nach `onChange` neu rendert. */
function Harness({ onChange }: { onChange?: (next: SectionState) => void }) {
  const [state, setState] = useState<SectionState>({ order: [...SECTION_KEYS], hidden: [], spans: {} });
  const change = (next: SectionState) => { setState(next); onChange?.(next); };
  return (
    <>
      {state.order.map((key, index) => (
        <SectionBar
          key={key}
          sectionKey={key}
          label={key}
          state={state}
          index={index}
          total={state.order.length}
          hints={HINTS}
          measure={measure}
          onChange={change}
        />
      ))}
    </>
  );
}

const grab = (label: string) => screen.getByLabelText(`Ziehen: ${label}`);

/** Zeiger auf einer Karte greifen und bis `clientY` ziehen. */
function dragTo(label: string, clientY: number) {
  fireEvent.pointerDown(grab(label), { pointerType: "mouse", button: 0 });
  fireEvent.pointerMove(window, { pointerType: "mouse", clientY });
}

describe("SectionBar", () => {
  it("zeigt die Beschriftung und blendet ausgeblendete Abschnitte als solche", () => {
    render(<SectionBar sectionKey="messages" label="Nachrichten" state={{ order: ["messages"], hidden: ["messages"], spans: {} }} index={0} total={1} hints={HINTS} measure={measure} onChange={() => {}} />);
    expect(screen.getByText("Nachrichten")).toBeTruthy();
    expect(screen.getByText(HINTS.hidden)).toBeTruthy();
    expect(document.querySelector(".sec-bar")?.className).toContain("is-off");
  });

  it("setzt is-dragging während des Zugs und danach wieder ab", () => {
    render(<Harness />);
    const bar = document.querySelector(".sec-bar") as HTMLElement;
    expect(bar.className).not.toContain("is-dragging");

    dragTo("messages", 60);
    expect(bar.className).toContain("is-dragging");

    fireEvent.pointerUp(window);
    expect(bar.className).not.toContain("is-dragging");
  });

  it("sortiert live um, sobald die Mittellinie einer anderen Karte ueberschritten wird", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);

    dragTo("messages", 60);
    // Mittellinie der ersten Karte noch nicht passiert -> nichts aendert.
    expect(seen).toHaveLength(0);

    fireEvent.pointerMove(window, { pointerType: "mouse", clientY: 160 });
    expect(seen.at(-1)).toEqual(["homework", "messages", "weather"]);

    fireEvent.pointerMove(window, { pointerType: "mouse", clientY: 260 });
    expect(seen.at(-1)).toEqual(["homework", "weather", "messages"]);
  });

  it("behaelt die Position, wenn der Zeiger unterhalb der letzten Karte ist", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);
    // Karte 3 belegt 200..300. Darunter darf nicht auf "Index 3" gesetzt
    // werden — dafuer gibt es keine Karte, der Rueckfall ist die aktuelle.
    dragTo("messages", 160);
    expect(seen.at(-1)).toEqual(["homework", "messages", "weather"]);
    fireEvent.pointerMove(window, { pointerType: "mouse", clientY: 400 });
    expect(seen.at(-1)).toEqual(["homework", "messages", "weather"]);
  });

  it("behaelt die Position, wenn der Zeiger oberhalb der ersten Karte ist", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);
    dragTo("messages", -50);
    expect(seen).toHaveLength(0);
  });

  it("bricht das Ziehen ab, wenn der Zeiger abgebrochen wird", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);
    const bar = document.querySelector(".sec-bar") as HTMLElement;

    dragTo("messages", 160);
    const afterDrag = seen.length;
    expect(afterDrag).toBeGreaterThan(0);

    fireEvent.pointerCancel(window);
    expect(bar.className).not.toContain("is-dragging");

    // Nach dem Abbruch darf kein weiterer Zug kommen.
    fireEvent.pointerMove(window, { pointerType: "mouse", clientY: 260 });
    expect(seen).toHaveLength(afterDrag);
  });

  it("bricht das Ziehen bei Fenster-Fokusverlust ab", () => {
    render(<Harness />);
    const bar = document.querySelector(".sec-bar") as HTMLElement;
    dragTo("messages", 60);
    expect(bar.className).toContain("is-dragging");
    fireEvent.blur(window);
    expect(bar.className).not.toContain("is-dragging");
  });

  it("verschiebt ueber die Knoepfe hoch und runter", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);

    fireEvent.click(screen.getByLabelText("Runter: messages"));
    expect(seen.at(-1)).toEqual(["homework", "messages", "weather"]);
    // Nach dem Verschieben ist "messages" nicht mehr die letzte Karte.
    fireEvent.click(screen.getByLabelText("Hoch: messages"));
    expect(seen.at(-1)).toEqual(["messages", "homework", "weather"]);
  });

  it("blendet ueber den Knopf aus und wieder ein", () => {
    const seen: SectionState[] = [];
    render(<Harness onChange={(next) => seen.push(next)} />);

    fireEvent.click(screen.getByLabelText("Ausblenden: messages"));
    expect(seen.at(-1)?.hidden).toEqual(["messages"]);
    fireEvent.click(screen.getByLabelText("Einblenden: messages"));
    expect(seen.at(-1)?.hidden).toEqual([]);
  });

  it("wechselt zwischen halber und voller Breite", () => {
    const seen: SectionState[] = [];
    render(<Harness onChange={(next) => seen.push(next)} />);

    fireEvent.click(screen.getByLabelText("Schmal: messages"));
    expect(seen.at(-1)?.spans).toEqual({ messages: 6 });
    fireEvent.click(screen.getByLabelText("Breit: messages"));
    expect(seen.at(-1)?.spans).toEqual({ messages: 12 });
  });

  it("sperrt Hoch am Anfang und Runter am Ende", () => {
    render(<Harness />);
    expect((screen.getByLabelText("Hoch: messages") as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByLabelText("Runter: messages") as HTMLButtonElement).disabled).toBe(false);
    expect((screen.getByLabelText("Hoch: weather") as HTMLButtonElement).disabled).toBe(false);
    expect((screen.getByLabelText("Runter: weather") as HTMLButtonElement).disabled).toBe(true);
  });

  it("setzt den Abschnittsnamen in die Beschriftung der Richtungsknoepfe", () => {
    render(<Harness />);
    // Ohne Aufloesung blieb hier "Hoch: {name}" stehen.
    expect(screen.getByLabelText("Hoch: messages")).toBeTruthy();
    expect(screen.getByLabelText("Runter: weather")).toBeTruthy();
    expect(screen.queryByLabelText(/\{name\}/)).toBeNull();
  });

  it("ignoriert ein Ziehen mit der rechten Maustaste", () => {
    const seen: string[][] = [];
    render(<Harness onChange={(next) => seen.push(next.order)} />);
    fireEvent.pointerDown(grab("messages"), { pointerType: "mouse", button: 2 });
    fireEvent.pointerMove(window, { pointerType: "mouse", clientY: 260 });
    expect(seen).toHaveLength(0);
  });
});
