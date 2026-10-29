"use client";

import { useEffect, useMemo, useState } from "react";
import { t } from "../../lib/i18n";
import { useLocale } from "../../lib/locale-context";
import { api } from "../../lib/api";
import { formatDate } from "../../lib/format";
import type { AgendaItem, Substitution } from "../../lib/types";
import { DateField } from "../date-field";
import { Icon } from "../icon";
import { SubstitutionList } from "../substitution-list";
import { Notice, PageTitle } from "../ui";

export function AgendaView() {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const today = new Date().toISOString().slice(0, 10); const [day, setDay] = useState(today); const [items, setItems] = useState<AgendaItem[]>([]); const [substitutions, setSubstitutions] = useState<Substitution[]>([]); const [weekLabel, setWeekLabel] = useState(""); const [error, setError] = useState(""); const [loading, setLoading] = useState(true); const [refreshKey, setRefreshKey] = useState(0);
  const bounds = useMemo(() => { const selected = new Date(`${day}T12:00:00`); const start = new Date(selected); const end = new Date(selected); start.setDate(selected.getDate() - 30); end.setDate(selected.getDate() + 60); return { from: start.toISOString().slice(0, 10), until: end.toISOString().slice(0, 10) }; }, [day]);
  useEffect(() => { let live = true; setLoading(true); const params = new URLSearchParams({ since: bounds.from, until: bounds.until }); if (refreshKey) params.set("refresh", "1"); Promise.all([api<{ items: AgendaItem[] }>(`/school/agenda?${params}`), api<{ week_label: string; days: typeof substitutions }>(`/substitutions/week?day=${day}`)]).then(([calendar, changes]) => { if (!live) return; setItems(calendar.items); setSubstitutions(changes.days); setWeekLabel(changes.week_label); setError(""); }).catch((e: Error) => { if (live) setError(e.message); }).finally(() => { if (live) setLoading(false); }); return () => { live = false; }; }, [bounds.from, bounds.until, day, refreshKey]);
  function addWeek(amount: number) { const date = new Date(`${day}T12:00:00`); date.setDate(date.getDate() + amount * 7); setDay(date.toISOString().slice(0, 10)); }
  const labels: Record<string, string> = { event: t("agenda.kindEvent"), exam: t("agenda.kindExam"), attendance: t("agenda.kindAttendance") };
  return <><PageTitle eyebrow={t("agenda.eyebrow")} title={t("agenda.title")} detail={weekLabel || t("agenda.detailFallback")} /><Notice error={error} /><form className="day-nav" onSubmit={(event) => { event.preventDefault(); setRefreshKey((key) => key + 1); }}><button className="btn btn-light btn-sm" type="button" onClick={() => addWeek(-1)}><Icon name="left" />{t("agenda.prevWeek")}</button><div className="field"><label htmlFor="agenda-day">{t("agenda.weekLabel")}</label><DateField id="agenda-day" ariaLabel={t("agenda.weekLabel")} value={day} onChange={setDay} /></div><button className="btn btn-light btn-sm" type="button" onClick={() => setDay(today)}><Icon name="calendar" />{t("agenda.thisWeek")}</button><button className="btn btn-light btn-sm" type="button" onClick={() => addWeek(1)}>{t("agenda.nextWeek")}<Icon name="right" /></button><button className="btn btn-primary btn-sm" type="submit"><Icon name="refresh" />{t("agenda.refresh")}</button></form>
    <div className="agenda-sections"><section className="agenda-section" aria-labelledby="agenda-heading"><h2 id="agenda-heading">{t("agenda.calTitle")}</h2>{items.map((item) => <article className="card agenda-row" key={item.id}><time>{formatDate(item.date)}</time><span className={`tag tag-${item.kind}`}>{labels[item.kind] ?? item.kind}</span><div><strong>{item.title ?? item.text}</strong>{item.subject && <p className="agenda-meta">{item.subject}</p>}</div></article>)}{!items.length && !loading && <div className="card agenda-empty">{t("agenda.emptyCal")}</div>}</section>
      <SubstitutionList days={substitutions} loading={loading} headingId="substitution-heading" /></div>{loading && <p className="muted" aria-live="polite">{t("agenda.loadingCal")}</p>}</>;
}
