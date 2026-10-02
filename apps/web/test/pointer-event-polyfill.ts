/**
 * Polyfill fuer `PointerEvent`: jsdom kennt nur `MouseEvent`, wodurch
 * `fireEvent.pointerMove` ohne `clientY` ankommt und der Ziehen-Test
 * nichts messen koennte. Reicht die Felder, die `section-bar.tsx`
 * tatsaechlich liest (`clientY`, `pointerType`, `button`).
 *
 * Nur fuer Komponenten-Tests in jsdom noetig; die Logik-Tests in
 * `src/lib/` laufen weiterhin in `node`.
 */

interface PointerInit extends MouseEventInit {
  pointerId?: number;
  pointerType?: string;
  isPrimary?: boolean;
}

if (typeof globalThis.PointerEvent === "undefined") {
  class PointerEventPolyfill extends MouseEvent {
    readonly pointerId: number;
    readonly pointerType: string;
    readonly isPrimary: boolean;

    constructor(type: string, init: PointerInit = {}) {
      super(type, init);
      this.pointerId = init.pointerId ?? 1;
      this.pointerType = init.pointerType ?? "mouse";
      this.isPrimary = init.isPrimary ?? true;
    }
  }
  globalThis.PointerEvent = PointerEventPolyfill as unknown as typeof PointerEvent;
}

export {};
