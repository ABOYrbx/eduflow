"use client";

import { useEffect, useMemo, useState } from "react";
import { localeTag, t } from "../../lib/i18n";
import { useLocale } from "../../lib/locale-context";
import { api } from "../../lib/api";
import type { Grade, Page } from "../../lib/types";
import { Icon } from "../icon";
import { SearchField } from "../search-field";
import { Empty, Notice, PageTitle } from "../ui";

function gradeTerm(dateIso: string) {
  const parsed = /^\d{4}-\d{2}-\d{2}$/.test(dateIso) ? new Date(`${dateIso}T12:00:00`) : new Date();
  const schoolYear = parsed.getFullYear() - (parsed.getMonth() < 8 ? 1 : 0);
  const half = parsed.getMonth() < 8 && parsed.getMonth() !== 0 ? 2 : 1;
  return `${schoolYear}-H${half}`;
}
function currentGradeTerm() { return gradeTerm(new Date().toISOString().slice(0, 10)); }
function gradeTermLabel(key: string) {
  const [year = "", half = "1"] = key.split("-H");
  return t("grades.halfYear", { half, a: year.slice(-2), b: String(Number(year) + 1).slice(-2) });
}
function weightedAverage(items: Grade[]) {
  const numeric = items.filter((item) => item.grade_num !== null && item.grade_num >= 1 && item.grade_num <= 6);
  const weight = numeric.reduce((total, item) => total + (item.weight > 0 ? item.weight : 1), 0);
  if (!weight) return "–";
  return (numeric.reduce((total, item) => total + item.grade_num! * (item.weight > 0 ? item.weight : 1), 0) / weight).toLocaleString(localeTag(), { maximumFractionDigits: 2 });
}

export function GradesView() {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const [grades, setGrades] = useState<Grade[]>([]); const [error, setError] = useState(""); const [refreshing, setRefreshing] = useState(false); const [term, setTerm] = useState(currentGradeTerm()); const [query, setQuery] = useState("");
  async function load(refresh = false) { setRefreshing(refresh); try { const result = await api<Page<Grade>>(`/grades?limit=200${refresh ? "&refresh=1" : ""}`); setGrades(result.items); setError(""); } catch (e) { setError((e as Error).message); } finally { setRefreshing(false); } }
  useEffect(() => { void load(); }, []);
  const terms = useMemo(() => Array.from(new Set(grades.map((grade) => gradeTerm(grade.date_iso)))).sort((a, b) => b.localeCompare(a)), [grades]);
  useEffect(() => { if (terms.length && !terms.includes(term)) setTerm(terms[0]); }, [term, terms]);
  const inTerm = useMemo(() => grades.filter((grade) => gradeTerm(grade.date_iso) === term), [grades, term]);
  const normalizedQuery = query.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag()).trim();
  const groups = useMemo(() => inTerm.filter((grade) => !normalizedQuery || [grade.subject, grade.title, grade.teacher].join(" ").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag()).includes(normalizedQuery)).reduce<Record<string, Grade[]>>((result, grade) => { (result[grade.subject] ??= []).push(grade); return result; }, {}), [inTerm, normalizedQuery]);
  return <><PageTitle eyebrow={t("grades.eyebrow")} title={t("nav.grades")} detail={t("grades.detailCount", { count: inTerm.length, avg: weightedAverage(inTerm) })} /><Notice error={error} />
    <div className="grades-bar anim-in"><div className="view-toggle" role="tablist" aria-label={t("grades.halfYearAria")}>{terms.map((key) => <button type="button" role="tab" aria-selected={term === key} className={term === key ? "active" : ""} key={key} onClick={() => setTerm(key)}>{gradeTermLabel(key)} ({grades.filter((grade) => gradeTerm(grade.date_iso) === key).length})</button>)}</div><div className="grades-tools"><div className="search-field grades-search"><SearchField className="input-pill" ariaLabel={t("grades.searchAria")} placeholder={t("grades.searchPlaceholder")} value={query} onChange={setQuery} /></div><button className="btn btn-light btn-sm" disabled={refreshing} onClick={() => void load(true)}><Icon name="refresh" />{refreshing ? t("common.loading") : t("grades.refresh")}</button></div></div>
    {Object.entries(groups).map(([subject, rows]) => <section className="subj card anim-in" key={subject}><div className="subj-head"><div className="subj-title"><h3>{subject}</h3><div className="meta">{rows.length} {rows.length === 1 ? t("grades.noteOne") : t("nav.grades")}</div></div><div className={`subj-avg ${weightedAverage(rows) === "–" ? "subj-avg-none" : ""}`} title={t("grades.avgTitle")}>Ø {weightedAverage(rows)}</div></div><div className="chips">{rows.map((grade) => <span className={`chip ${grade.badge}`} key={grade.id} title={`${grade.title} · ${grade.date_display}${grade.weight_display ? ` · ${t("grades.colWeight")} ${grade.weight_display}` : ""}`}>{grade.grade_display}{grade.weight_display && <small>{grade.weight_display}</small>}</span>)}</div><details><summary>{t("grades.details")}</summary><div className="tt-scroll"><table className="g-table"><thead><tr><th>{t("grades.colDate")}</th><th>{t("grades.colTopic")}</th><th>{t("grades.noteOne")}</th><th>{t("grades.colWeight")}</th><th>{t("grades.colTeacher")}</th><th>{t("grades.colClassAvg")}</th><th>{t("grades.colComment")}</th></tr></thead><tbody>{rows.map((grade) => <tr key={grade.id}><td className="nowrap">{grade.date_display}</td><td>{grade.title}</td><td><strong>{grade.grade_display}</strong>{grade.grade_sub && <span className="dim"> · {grade.grade_sub}</span>}</td><td className="nowrap">{grade.weight_display || t("grades.weightOnce")}</td><td>{grade.teacher || "–"}</td><td className="nowrap">{grade.class_avg_display || "–"}</td><td>{grade.comment || "–"}</td></tr>)}</tbody></table></div></details></section>)}
    {!Object.keys(groups).length && !error && <Empty>{grades.length ? t("grades.emptyFiltered") : t("grades.empty")}</Empty>}</>;
}
