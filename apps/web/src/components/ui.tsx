"use client";

/**
 * Kleine Bausteine, die alle Ansichten brauchen: Seitenkopf, Fehlernotiz
 * und Leerzustand. Eigene Datei, weil `views/*` und `sessions-view` sie
 * brauchen — sonst müssten sie über `dashboard-app` importieren und es
 * entstünde ein Zyklus (Dashboard → Ansicht → Dashboard).
 */

export function PageTitle({ eyebrow, title, detail }: { eyebrow: string; title: string; detail?: string }) {
  return <div className="page-head anim-in"><span className="eyebrow">{eyebrow}</span><h1>{title}</h1>{detail && <p className="stats">{detail}</p>}</div>;
}

/** Fehlermeldung. `error` leer = nichts gerendert. */
export function Notice({ error }: { error: string }) {
  return error ? <p className="notice-error" role="alert">{error}</p> : null;
}

/** Leerzustand (`children` ist der fertig übersetzte Text). */
export function Empty({ children }: { children: string }) {
  return <p className="empty">{children}</p>;
}
