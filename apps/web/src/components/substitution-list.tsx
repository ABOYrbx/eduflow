"use client";

import { localeTag, t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";
import { weekdayLabel } from "../lib/date-field";
import type { Substitution } from "../lib/types";

/**
 * Vertretungswoche — von `timetable/week` UND `school/agenda` benutzt.
 * Das Markup war vorher zweimal kopiert; Unterschiede waren nur die
 * Zusatzklasse, die Überschrift-Verknüpfung und, auf der Agenda, das
 * Warten auf den Ladezustand.
 */

/** Aktion der Vertretung: Entfall, zusätzliche Stunde oder Verschiebung. */
function actionLabel(action: string): string {
  if (action === "remove") return t("overview.cancelled");
  if (action === "add") return t("agenda.actionAdd");
  return t("agenda.actionChange");
}

export function SubstitutionList({
  days,
  className = "",
  loading = false,
  headingId,
}: {
  days: Substitution[];
  /** Zusatzklasse auf dem `<section>` (Stundenplan: `timetable-substitutions`). */
  className?: string;
  /** Vor dem Laden lieber gar nichts zeigen als „leer" (Agenda). */
  loading?: boolean;
  headingId: string;
}) {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern

  return (
    <section className={`agenda-section${className ? ` ${className}` : ""}`} aria-labelledby={headingId}>
      <h2 id={headingId}>{t("agenda.subsTitle")}</h2>
      {days.some((entry) => entry.changes.length)
        ? days.map((entry) => entry.changes.map((change, index) => (
            <div className="agenda-day" key={`${entry.date}-${index}`}>
              <h3>{weekdayLabel(entry.date, localeTag(), entry.day_label)}</h3>
              <article className="card agenda-change">
                <span className="agenda-period">{t("timetable.lessonHour", { lesson: change.lesson })}</span>
                <div>
                  <strong>{change.title}</strong>
                  <p className="agenda-meta">{change.class ? t("agenda.classLabel", { cls: change.class }) : t("agenda.planChange")}</p>
                </div>
                <span className={`tag ${change.action === "remove" ? "tag-red" : change.action === "add" ? "tag-blue" : "tag-amber"}`}>
                  {actionLabel(change.action)}
                </span>
              </article>
            </div>
          )))
        : !loading && <div className="card agenda-empty">{t("agenda.emptySubs")}</div>}
    </section>
  );
}
