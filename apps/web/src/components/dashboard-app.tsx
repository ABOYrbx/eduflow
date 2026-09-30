"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { FormEvent, Fragment, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { localeTag, t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";
import { normalizeHidden, normalizeOrder, SECTION_KEYS } from "../lib/section-layout";
import { Icon } from "./icon";
import { LanguagePicker } from "./language-picker";
import { SectionEditor, type SectionLayout } from "./section-editor";
import { Select } from "./select-field";

declare global {
  interface Window {
    EduFlowTheme?: {
      choice(): string;
      setChoice(value: string): void;
      accent(): string;
      setAccent(value: string): void;
    };
  }
}

type ApiError = { error?: string; code?: string };
type Page<T> = { items: T[]; total: number; limit: number; offset: number; counts?: Record<string, number>; cache_info?: string };
type Message = { id: number; text: string; author: string; recipient: string; type: string; type_label: string; timestamp: string; timestamp_iso: string; additional_data?: Record<string, unknown>; attachments?: Array<{ name: string; url: string }>; is_starred: boolean; is_done?: boolean; done_at?: string; reaction_count: number };
type Thread = { likes: Array<{ name: string; date: string }>; replies: Array<{ name: string; date: string; text: string }> };
type Homework = { id: number; title: string; subject: string; description: string; teacher: string; author?: string; assigned?: string; assigned_iso?: string; due: string; due_display: string; status: string; is_done: boolean; is_hidden: boolean; is_starred?: boolean; done_at?: string; type: string; type_label?: string };
type Lesson = { period: string; time: string; title: string; teachers: string; rooms: string; is_lernzeit: boolean; is_cancelled: boolean; is_online: boolean; is_event?: boolean };
type Grade = { id: number; title: string; subject: string; teacher: string; date_display: string; date_iso: string; grade_display: string; grade_num: number | null; weight: number; weight_display: string; grade_sub: string; badge: string; class_avg_display: string; comment: string };
type AgendaItem = { id: number; kind: string; date: string; title?: string; text: string; subject?: string };
type Settings = { schema: Array<{ key: string; kind: string; label: string; options?: string[][]; default: unknown; min?: number; max?: number; hint?: string; maxlength?: number; section?: string; placeholder?: string }>; values: Record<string, unknown> };
type Weather = { city: string; today: { temp: number; max: number; min: number; desc: string; icon: string }; tomorrow: { max: number; min: number; desc: string; icon?: string }; day3: { max: number; min: number; desc: string; icon?: string } };

/** Navigation — bewusst als Funktion, damit `t()` erst beim Rendern liest
 *  und ein Sprachwechsel die Beschriftungen mitnimmt. */
const nav = () => [{ href: "/", label: t("nav.overview") }, { href: "/messages", label: t("nav.messages") }, { href: "/homework", label: t("nav.homework") }, { href: "/grades", label: t("nav.grades") }, { href: "/timetable", label: t("nav.timetable") }, { href: "/agenda", label: t("nav.agenda") }];


async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`/api/v1${path}`, { ...init, cache: "no-store", headers: { ...(init?.body ? { "content-type": "application/json" } : {}), ...init?.headers } });
  const body = await response.json().catch(() => ({})) as T & ApiError;
  if (!response.ok) throw new Error(body.error ?? t("common.requestFailed"));
  return body;
}

function formatDate(value: string) { const date = new Date(value); return Number.isNaN(date.valueOf()) ? value : date.toLocaleDateString(localeTag(), { day: "2-digit", month: "long" }); }
function weatherIcon(desc: unknown, icon?: string) {
  if (icon) {
    const code = icon.slice(0, 2);
    if (code === "01") return "☀";
    if (code === "02" || code === "03" || code === "04" || code === "50") return "☁";
    if (code === "09" || code === "10" || code === "11" || code === "13") return "☂";
  }
  const text = String(desc ?? "").toLowerCase();
  if (/(regen|rain|drizzle|shower|thunder|storm|schauer|gewitter|niesel|schnee|snow|hagel|hail)/.test(text)) return "☂";
  if (/(bewölkt|bewoelkt|wolk|bedeckt|cloud|overcast|nebel|fog|mist|dunst)/.test(text)) return "☁";
  return "☀";
}
function lessonStartIndex(lessons: Lesson[], now: Date) {
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  const partsFor = (lesson: Lesson) => lesson.time.split("–").map((time) => time.trim().split(":").map(Number));
  for (let index = 0; index < lessons.length; index++) {
    const lesson = lessons[index]; if (!lesson || lesson.is_cancelled) continue;
    const [start, end] = partsFor(lesson); if (start?.length !== 2 || end?.length !== 2 || !start.every(Number.isFinite) || !end.every(Number.isFinite)) continue;
    if (nowMinutes >= start[0] * 60 + start[1] && nowMinutes <= end[0] * 60 + end[1]) return index;
  }
  for (let index = 0; index < lessons.length; index++) {
    const lesson = lessons[index]; if (!lesson || lesson.is_cancelled) continue;
    const [start] = partsFor(lesson); if (start?.length === 2 && start.every(Number.isFinite) && nowMinutes < start[0] * 60 + start[1]) return index;
  }
  return Math.max(lessons.length - 1, 0);
}
function messageAttachments(message: Message) {
  if (message.attachments?.length) return message.attachments.map((item) => item.name);
  const filename = (message.additional_data ?? {}).filename;
  return typeof filename === "string" && filename ? [filename] : [];
}
function PageTitle({ eyebrow, title, detail }: { eyebrow: string; title: string; detail?: string }) { return <div className="page-head anim-in"><span className="eyebrow">{eyebrow}</span><h1>{title}</h1>{detail && <p className="stats">{detail}</p>}</div>; }
function Notice({ error }: { error: string }) { return error ? <p className="notice-error" role="alert">{error}</p> : null; }
function Empty({ children }: { children: string }) { return <p className="empty">{children}</p>; }

export function DashboardApp({ username }: { username: string }) {
  const path = usePathname(); const router = useRouter();
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const items = nav();
  const active = path === "/mehr" ? "Mehr" : items.find((item) => item.href === path)?.label ?? t("nav.settings");
  const [logoutError, setLogoutError] = useState("");
  const navRef = useRef<HTMLElement>(null);
  const [navEdges, setNavEdges] = useState({ start: false, end: false });
  useEffect(() => {
    const el = navRef.current;
    if (!el) return;
    const update = () => setNavEdges({ start: el.scrollLeft > 4, end: el.scrollLeft + el.clientWidth < el.scrollWidth - 4 });
    update();
    el.addEventListener("scroll", update, { passive: true });
    const observer = new ResizeObserver(update);
    observer.observe(el);
    window.addEventListener("resize", update);
    return () => { el.removeEventListener("scroll", update); observer.disconnect(); window.removeEventListener("resize", update); };
  }, []);
  function scrollNav(direction: -1 | 1) {
    const el = navRef.current;
    if (!el) return;
    const pill = el.querySelector<HTMLElement>(".nav-pill");
    el.scrollBy({ left: direction * (pill ? pill.offsetWidth + 2 : 120) * 2, behavior: "smooth" });
  }
  async function logout() { const response = await fetch("/api/auth/logout", { method: "POST" }); if (response.ok) router.replace("/login"); else setLogoutError(t("nav.logoutFailed")); }
  return <>
    <div className="nav-wrap"><div className="container nav">
      <Link className="nav-logo" href="/" aria-label={t("nav.logoAria")}><img src="/icons/icon.png" alt="" /></Link>
      {/* Beide Knoepfe bleiben immer an Ort und Stelle. Am Anfang bzw. Ende
          werden sie unsichtbar statt abgeblendet - so verschwinden sie wie
          gewuenscht, ohne dass die Leiste springt. Vorher wurden sie per
          && weggeschluckt: dadurch bekam .nav-mid mehr Platz, der Inhalt
          ueberlief nicht mehr, und der Knopf kam sofort wieder zurueck. */}
      <button className={`nav-scroll nav-scroll-start${navEdges.start ? "" : " is-idle"}`} type="button" tabIndex={-1} aria-label={t("nav.scrollBack")} disabled={!navEdges.start} onClick={() => scrollNav(-1)}><Icon name="left" /></button>
      <nav className="nav-mid" aria-label={t("nav.mainAria")} ref={navRef}>{items.map((item) => <Link className={`nav-pill ${active === item.label ? "active" : ""}`} key={item.href} href={item.href}>{item.label}</Link>)}</nav>
      <button className={`nav-scroll nav-scroll-end${navEdges.end ? "" : " is-idle"}`} type="button" tabIndex={-1} aria-label={t("nav.scrollForward")} disabled={!navEdges.end} onClick={() => scrollNav(1)}><Icon name="right" /></button>
      <div className="nav-cta"><div className="profile-wrap">
        <button className="avatar-btn" type="button" aria-haspopup="true" aria-expanded="false" aria-label={t("nav.profileAria")} title={username}>{username.slice(0, 1).toLocaleUpperCase(localeTag())}</button>
        <div className="profile-menu" role="menu"><div className="pm-head"><div className="t">{t("nav.profileTitle")}</div><div className="u">{username}</div></div><div className="pm-div" />
          <Link className="pm-link" href="/settings" role="menuitem">{t("nav.settings")}</Link>
          <button className="pm-link pm-danger" role="menuitem" type="button" onClick={logout}><Icon name="logout" />{t("nav.logout")}</button>
        </div>
      </div></div>
    </div></div>
    <main className="container container-wide">
      <Notice error={logoutError} />
      {path === "/" && <OverviewView username={username} />}
      {path === "/messages" && <MessagesView />}
      {path === "/homework" && <HomeworkView />}
      {path === "/grades" && <GradesView />}
      {path === "/timetable" && <TimetableView />}
      {path === "/agenda" && <AgendaView />}
      {(path === "/settings" || path === "/mehr") && <SettingsView />}
      <footer><p>{t("nav.footer")}</p></footer>
    </main>
  </>;
}

function OverviewView({ username }: { username: string }) {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const [messages, setMessages] = useState<Message[]>([]); const [homework, setHomework] = useState<Homework[]>([]); const [counts, setCounts] = useState<Record<string, number>>({}); const [lessons, setLessons] = useState<Lesson[]>([]); const [weather, setWeather] = useState<Weather | null>(null); const [settings, setSettings] = useState<Settings | null>(null); const [error, setError] = useState(""); const [clock, setClock] = useState<Date | null>(null); const [lessonIndex, setLessonIndex] = useState(0); const [loaded, setLoaded] = useState(false);
  const [order, setOrder] = useState<string[]>(SECTION_KEYS.slice()); const [hidden, setHidden] = useState<string[]>([]);
  useEffect(() => { const tick = () => setClock(new Date()); tick(); const timer = window.setInterval(tick, 1000); return () => window.clearInterval(timer); }, []);
  useEffect(() => { let live = true; Promise.all([api<Page<Message>>("/messages?limit=4"), api<Page<Homework>>("/homework?limit=5&status=offen"), api<{ lessons: Lesson[] }>("/timetable/day"), api<Weather>("/wetter?city=Berlin"), api<Settings>("/settings")]).then(([m, h, t, w, s]) => { if (!live) return; setMessages(m.items); setHomework(h.items); setCounts(h.counts ?? {}); const schoolDayLessons = t.lessons.filter((lesson) => !lesson.is_event); setLessons(schoolDayLessons); setLessonIndex(lessonStartIndex(schoolDayLessons, new Date())); setWeather(w); setSettings(s); setOrder(normalizeOrder(s.values)); setHidden(normalizeHidden(s.values)); }).catch((e: Error) => { if (live) setError(e.message); }).finally(() => { if (live) setLoaded(true); }); return () => { live = false; }; }, []);
  const schoolLessons = lessons.filter((lesson) => !lesson.is_event); const selectedLesson = schoolLessons[Math.min(lessonIndex, Math.max(schoolLessons.length - 1, 0))]; const visibleOrder = order.filter((key) => !hidden.includes(key));
  const sections: Record<string, React.ReactNode> = {
    homework: <section className="ov-col anim-in" style={{ "--d": "80ms" } as React.CSSProperties} key="homework"><div className="ov-col-head"><h2>{t("nav.homework")}</h2><div className="ov-actions"><Link className="btn btn-primary btn-sm" href="/homework">{t("overview.allTasks")}</Link></div></div><div className="ov-bundle card"><span><strong>{counts.offen ?? 0}</strong> {t("homework.open")}</span><span className="sep">·</span><span><strong className="n-danger">{counts.ueberfaellig ?? 0}</strong> {t("homework.overdue")}</span><span className="sep">·</span><span><strong className="n-ok">{counts.erledigt ?? 0}</strong> {t("homework.done")}</span></div>{homework.slice(0, 5).map((task) => <article className={`hw card ${task.status === "überfällig" ? "st-ueber" : task.status === "heute fällig" ? "st-heute" : task.is_done ? "st-erledigt" : "st-offen"} ${task.is_done ? "is-done" : ""}`} key={task.id}><h3>{task.title}</h3><div className="meta"><span className="tag tag-muted">{task.subject}</span><span className="tag tag-blue">{homeworkStatusPill(task.status)}</span><span>{t("homework.dueLabel")} <strong>{task.due_display}</strong></span><span>{task.teacher}</span></div><div className="text">{task.description || t("common.noDescription")}</div></article>)}{!homework.length && <Empty>{t("overview.emptyHomework")}</Empty>}</section>,
    messages: <section className="ov-col anim-in" style={{ "--d": "80ms" } as React.CSSProperties} key="messages"><div className="ov-col-head"><h2>{t("nav.messages")} <span className="muted">· {t("overview.newMessages", { count: messages.length })}</span></h2><div className="ov-actions"><Link className="btn btn-light btn-sm" href="/messages">{t("overview.allMessages")}</Link></div></div>{messages.map((message) => <article className="card overview-message" key={message.id}><div className="meta"><strong>{message.author || t("common.school")}</strong><span>{message.timestamp}</span></div><div className="text">{message.text || message.type_label}</div></article>)}{!messages.length && <Empty>{t("overview.emptyMessages")}</Empty>}</section>,
    weather: settings?.values.ov_wetter === false ? null : <section className="ov-col anim-in" style={{ "--d": "60ms" } as React.CSSProperties} key="weather"><div className="ov-col-head"><h2>{t("overview.weather")}</h2></div>{weather ? <div className="weather-card"><div className="wx-summary"><span className="wx-summary-title">{t("overview.weather")}</span><span className="wx-summary-city">{weather.city}</span></div><div className="wx-forecast">{[[t("overview.today"), weather.today.temp, weather.today.min, weather.today.max, weather.today.desc, weather.today.icon], [t("overview.tomorrow"), null, weather.tomorrow.min, weather.tomorrow.max, weather.tomorrow.desc, weather.tomorrow.icon], [t("overview.dayAfter"), null, weather.day3.min, weather.day3.max, weather.day3.desc, weather.day3.icon]].map(([label, temp, min, max, desc, icon]) => <div className="wx-day" key={String(label)}><span className="wx-l">{label}</span><span className="wx-img" aria-hidden="true">{weatherIcon(desc, typeof icon === "string" ? icon : undefined)}</span><strong className="wx-temp">{temp == null ? `${max}°` : `${temp}°`}</strong><span className="wx-cond">{desc}</span><span className="wx-range">{min}° – {max}°</span></div>)}</div></div> : <div className="weather-card"><div className="wx-unavailable"><span className="wx-unavailable-mark">☼</span><span><strong>{t("overview.weatherUnavailable")}</strong><small>{t("overview.weatherHint")}</small></span></div></div>}</section>,
  };
  return <><div className="ov-top anim-in"><div className="clock-card"><div className="clock-time">{clock?.toLocaleTimeString(localeTag(), { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: settings?.values?.time_format === "12h" }) ?? "--:--:--"}</div><div className="clock-date">{clock?.toLocaleDateString(localeTag(), { weekday: "long", day: "numeric", month: "long" }) ?? ""}</div></div><div className="now-card now-right"><div className="now-top"><span className="l">{t("overview.lessonsToday")}</span><span className="now-count">{schoolLessons.length > 1 ? `${Math.min(lessonIndex + 1, schoolLessons.length)} / ${schoolLessons.length}` : ""}</span></div>{selectedLesson ? <><div className="n">{selectedLesson.title}</div><div className="s">{t("timetable.lessonHour", { lesson: selectedLesson.period })} · {selectedLesson.time}{selectedLesson.rooms ? ` · ${t("overview.room", { rooms: selectedLesson.rooms })}` : ""}{selectedLesson.teachers ? ` · ${selectedLesson.teachers}` : ""}</div><div className="now-tags">{selectedLesson.is_cancelled && <span className="tag tag-muted">{t("overview.cancelled")}</span>}{selectedLesson.is_online && <span className="tag tag-soft">{t("overview.online")}</span>}</div></> : loaded ? <><div className="n">{t("overview.free")}</div><div className="s">{t("overview.noLessonsToday")}</div></> : <><div className="n">{t("overview.loading")}</div><div className="s">{t("overview.loadingTimetable")}</div></>}<div className="now-nav"><button className="now-arrow" aria-label={t("overview.prevLesson")} onClick={() => setLessonIndex((i) => Math.max(0, i - 1))}>‹</button><Link className="now-link" href="/timetable">{t("nav.timetable")}</Link><button className="now-arrow" aria-label={t("overview.nextLesson")} onClick={() => setLessonIndex((i) => Math.min(schoolLessons.length - 1, i + 1))}>›</button></div></div></div><Notice error={error} /><div className="ov-grid">{visibleOrder.map((key) => sections[key])}</div></>;
}

function MessagesView() {
  const [items, setItems] = useState<Message[]>([]); const [q, setQ] = useState(""); const [type, setType] = useState(""); const [since, setSince] = useState("2000-01-01"); const [selected, setSelected] = useState<Message | null>(null); const [composeOpen, setComposeOpen] = useState(false); const [thread, setThread] = useState<Thread | null>(null); const [recipients, setRecipients] = useState<Array<{ id: string; name: string; kind?: string; detail?: string }>>([]); const [recipientQuery, setRecipientQuery] = useState(""); const [error, setError] = useState(""); const [feedback, setFeedback] = useState(""); const [page, setPage] = useState(0); const [refreshing, setRefreshing] = useState(false);
  const load = useCallback(async (refresh = false) => {
    setRefreshing(refresh);
    try { const params = new URLSearchParams({ limit: "20", offset: String(page * 20), since }); if (q) params.set("q", q); if (type) params.set("type", type); if (refresh) params.set("refresh", "1"); const result = await api<Page<Message>>(`/messages?${params}`); setItems(result.items); setError(""); }
    catch (e) { setError((e as Error).message); } finally { setRefreshing(false); }
  }, [page, q, since, type]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { void api<{ items: Array<{ id: string; name: string; kind?: string; detail?: string }> }>("/recipients").then((r) => setRecipients(r.items)).catch(() => undefined); }, []);
  async function openThread(message: Message) { setComposeOpen(false); setSelected(message); setThread(await api<Thread>(`/messages/${message.id}/thread`).catch((e: Error) => { setError(e.message); return null; })); }
  async function send(event: FormEvent<HTMLFormElement>) { event.preventDefault(); const formElement = event.currentTarget; const form = new FormData(formElement); const recipientsValue = form.getAll("recipients").map(String); try { await api("/messages/send", { method: "POST", body: JSON.stringify({ recipients: recipientsValue, body: String(form.get("body") ?? "") }) }); setFeedback(t("messages.sentMessage")); formElement.reset(); setRecipientQuery(""); await load(true); } catch (e) { setError((e as Error).message); } }
  async function reply(event: FormEvent<HTMLFormElement>) { event.preventDefault(); if (!selected) return; const formElement = event.currentTarget; const form = new FormData(formElement); try { await api(`/messages/${selected.id}/reply`, { method: "POST", body: JSON.stringify({ body: String(form.get("body") ?? "") }) }); setFeedback(t("messages.sentReply")); await openThread(selected); formElement.reset(); } catch (e) { setError((e as Error).message); } }
  async function markRead() { try { const result = await api<{ marked: number }>("/messages/read", { method: "POST" }); setFeedback(t("messages.markedRead", { marked: result.marked })); await load(); } catch (e) { setError((e as Error).message); } }
  async function download(message: Message, idx: number, name: string) { try { const grant = await api<{ download_token: string }>("/messages/download-token", { method: "POST", body: JSON.stringify({ event_id: message.id, idx }) }); const response = await fetch(`/api/v1/messages/${message.id}/attachments/${idx}?dl=${encodeURIComponent(grant.download_token)}`); if (!response.ok) throw new Error(t("messages.attachFailed")); const blob = await response.blob(); const url = URL.createObjectURL(blob); const a = document.createElement("a"); a.href = url; a.download = name; a.click(); URL.revokeObjectURL(url); } catch (e) { setError((e as Error).message); } }
  const filteredRecipients = recipients.filter((recipient) => !recipientQuery || `${recipient.name} ${recipient.kind ?? ""} ${recipient.detail ?? ""}`.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag()).includes(recipientQuery.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag())));
  return <><PageTitle eyebrow={t("messages.eyebrow")} title={t("nav.messages")} detail={t("messages.detail")} /><Notice error={error} /><p className="notice-success" aria-live="polite">{feedback}</p>
    <section className="two-column"><div className="panel"><div className="panel-heading"><h2>{t("nav.messages")}</h2><div className="message-actions"><button className="secondary" type="button" onClick={() => void markRead()}><Icon name="check" />{t("messages.markAllRead")}</button><button className="primary" type="button" onClick={() => { setSelected(null); setThread(null); setComposeOpen(true); }}>{t("messages.new")}</button></div></div>
      <div className="filters"><input aria-label={t("messages.searchAria")} placeholder={t("messages.searchPlaceholder")} value={q} onChange={(e) => { setPage(0); setQ(e.target.value); }} /><Select className="filter-select" ariaLabel={t("messages.typeAria")} value={type} onChange={(next) => { setPage(0); setType(next); }} options={[{ value: "", label: t("messages.allTypes") }, { value: "sprava", label: t("nav.messages") }, { value: "news", label: t("messages.typeNews") }, { value: "anketa", label: t("messages.typePolls") }, { value: "chat", label: t("messages.typeChats") }, { value: "genotif", label: t("messages.typeNotices") }]} /><label className="since-filter">{t("messages.sinceLabel")}<input aria-label={t("messages.sinceLabel")} type="date" value={since} onChange={(e) => { setPage(0); setSince(e.target.value); }} /></label><button className="secondary" type="button" disabled={refreshing} onClick={() => void load(true)}>{refreshing ? t("common.loading") : t("homework.reload")}</button></div>
      {items.map((message) => { const attachments = messageAttachments(message); return <button className={`message-row ${selected?.id === message.id ? "selected" : ""}`} key={message.id} onClick={() => void openThread(message)}><span className="message-meta"><strong>{message.author || t("common.school")}</strong><small>{message.timestamp || formatDate(message.timestamp_iso)}</small></span><span className="row-snippet">{message.text || t("common.noText")}</span><span className="message-tags">{message.type !== "sprava" && <span className="tag tag-muted">{message.type_label}</span>}{message.is_starred && <span className="tag tag-soft">{t("messages.starred")}</span>}{message.is_done && <span className="tag tag-soft">{t("messages.done")}</span>}{message.reaction_count > 0 && <span className="tag tag-soft">♥ {message.reaction_count}</span>}{attachments.length > 0 && <span className="tag tag-blue">{attachments.length} {attachments.length === 1 ? t("messages.fileOne") : t("messages.fileMany")}</span>}</span></button>; })}
      {!items.length && <Empty>{t("messages.empty")}</Empty>}<div className="pager"><button className="secondary" disabled={page === 0} onClick={() => setPage((p) => Math.max(0, p - 1))}>{t("messages.back")}</button><span>{t("messages.page", { n: page + 1 })}</span><button className="secondary" disabled={items.length < 20} onClick={() => setPage((p) => p + 1)}>{t("messages.next")}</button></div></div>
      <div className="panel"><div className="panel-heading"><h2>{selected ? t("messages.messageLabel") : composeOpen ? t("messages.newMessage") : t("nav.messages")}</h2>{selected && <button className="secondary" onClick={() => { setSelected(null); setThread(null); setComposeOpen(true); }}>{t("messages.newMessage")}</button>}{!selected && composeOpen && <button className="secondary" onClick={() => setComposeOpen(false)}>{t("common.close")}</button>}</div>
        {selected ? <><div className="message-detail"><p className="muted">{selected.timestamp || formatDate(selected.timestamp_iso)} · {selected.type_label}</p><p><strong>{selected.author}</strong>{selected.recipient && <> → {selected.recipient}</>}</p><p>{selected.text || t("common.noText")}</p>{messageAttachments(selected).map((name, idx) => <button className="secondary attachment-button" key={`${name}-${idx}`} onClick={() => void download(selected, idx, name)}>{t("messages.loadFile", { name })}</button>)}</div>{thread && <><h3>{t("messages.conversation")}</h3>{thread.likes.map((like, i) => <p className="muted" key={`${like.name}-${i}`}>{t("messages.liked", { name: like.name, date: like.date })}</p>)}{thread.replies.map((reply, i) => <div className="reply" key={`${reply.name}-${i}`}><strong>{reply.name}</strong><p>{reply.text}</p></div>)}<form className="stack-form" onSubmit={reply}><label>{t("messages.replyLabel")}<textarea name="body" required rows={4} maxLength={5000} /></label><button className="primary">{t("messages.sendReply")}</button></form></>}</> : composeOpen ? <form className="stack-form" onSubmit={send}><label>{t("messages.recipientSearch")}<input aria-label={t("messages.recipientSearch")} placeholder={t("messages.recipientPlaceholder")} value={recipientQuery} onChange={(e) => setRecipientQuery(e.target.value)} /></label><label>{t("messages.recipients")}</label><div className="recipient-list">{filteredRecipients.map((recipient) => <label className="check" key={recipient.id}><input type="checkbox" name="recipients" value={recipient.id} /> {recipient.name}{recipient.kind && <span className="tag tag-muted">{recipient.kind === "teacher" ? t("grades.colTeacher") : t("messages.roleStudent")}</span>}</label>)}{!filteredRecipients.length && <p className="muted">{t("messages.noRecipients")}</p>}</div><small>{t("messages.multipleHint")}</small><label>{t("messages.messageLabel")}<textarea name="body" required rows={8} maxLength={5000} placeholder={t("messages.messagePlaceholder")} /></label><button className="primary">{t("messages.sendMessage")}</button></form> : <div className="detail-empty"><p><strong>{t("messages.noSelection")}</strong></p><p className="muted">{t("messages.selectHint")}</p><button className="btn btn-primary btn-sm" onClick={() => setComposeOpen(true)}>{t("messages.newMessageBtn")}</button></div>}</div></section></>;
}

function homeworkStatusLabel(status: string) {
  if (status === "offen") return t("homework.statusOpen");
  if (status === "überfällig") return t("homework.statusOverdue");
  if (status === "erledigt") return t("homework.statusDone");
  return status;
}
function homeworkStatusPill(status: string) {
  if (status === "offen") return t("homework.open");
  if (status === "heute fällig") return t("homework.dueToday");
  if (status === "überfällig") return t("homework.overdue");
  if (status === "erledigt") return t("homework.done");
  return status;
}
function HomeworkView() {
  const [items, setItems] = useState<Homework[]>([]); const [counts, setCounts] = useState<Record<string, number>>({}); const [status, setStatus] = useState("alle"); const [query, setQuery] = useState(""); const [since, setSince] = useState("2000-01-01"); const [includeTests, setIncludeTests] = useState(false); const [error, setError] = useState("");
  const load = useCallback(async () => { try { const params = new URLSearchParams({ status, q: query, since, limit: "200", include_tests: includeTests ? "1" : "0" }); const response = await api<Page<Homework>>(`/homework?${params}`); setItems(response.items); setCounts(response.counts ?? {}); setError(""); } catch (e) { setError((e as Error).message); } }, [status, query, since, includeTests]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { void api<Settings>("/settings").then((result) => { if (typeof result.values.hw_status === "string") setStatus(result.values.hw_status); if (typeof result.values.hw_tests === "boolean") setIncludeTests(result.values.hw_tests); }).catch(() => undefined); }, []);
  async function change(task: Homework, operation: "done" | "trash") { try { await api(`/homework/${task.id}/${operation}`, { method: "POST", body: JSON.stringify(operation === "done" ? { done: !task.is_done } : { hide: !task.is_hidden }) }); await load(); } catch (e) { setError((e as Error).message); } }
  const visibleLabel = status === "papierkorb" ? t("homework.trashLabel") : status === "alle" ? t("homework.entriesLabel") : homeworkStatusLabel(status);
  return <><PageTitle eyebrow={t("homework.eyebrow")} title={t("nav.homework")} detail={t("homework.detail")} /><Notice error={error} />
    <section className="stat-grid"><div className="stat"><div className="n">{items.length}</div><div className="l">{t("homework.loaded")}</div></div><div className="stat"><div className="n">{counts.offen ?? 0}</div><div className="l">{t("homework.open")}</div></div><div className="stat"><div className="n n-danger">{counts.ueberfaellig ?? 0}</div><div className="l">{t("homework.overdue")}</div></div><div className="stat"><div className="n n-ok">{counts.erledigt ?? 0}</div><div className="l">{t("homework.done")}</div></div></section>
    <div className="layout homework-layout"><aside className="sidebar"><h2>{t("homework.filterTitle")}</h2><div className="field"><label htmlFor="hw-search">{t("homework.searchLabel")}</label><input className="input-pill" id="hw-search" type="search" placeholder={t("homework.searchPlaceholder")} value={query} onChange={(event) => setQuery(event.target.value)} /></div><div className="field"><label id="hw-status-label">{t("homework.statusLabel")}</label><Select labelledBy="hw-status-label" value={status} onChange={setStatus} options={[{ value: "alle", label: t("overview.allTasks") }, { value: "offen", label: t("homework.statusOpen") }, { value: "überfällig", label: t("homework.statusOverdue") }, { value: "erledigt", label: t("homework.statusDone") }, { value: "papierkorb", label: t("homework.trashWithCount", { count: counts.papierkorb ?? 0 }) }]} /></div><div className="field"><label htmlFor="hw-since">{t("messages.sinceLabel")}</label><input className="input-pill" id="hw-since" type="date" value={since} onChange={(event) => setSince(event.target.value)} /></div><label className="check"><input type="checkbox" checked={includeTests} onChange={(event) => setIncludeTests(event.target.checked)} /> {t("homework.includeTests")}</label><button className="btn btn-primary" type="button" onClick={() => void load()}>{t("homework.reload")}</button>{(counts.papierkorb ?? 0) > 0 && <button className="btn btn-light" type="button" onClick={() => setStatus("papierkorb")}>{t("homework.trashWithCount", { count: counts.papierkorb })}</button>}</aside>
      <div className="feed"><div className="feed-head"><p className="stats">{t("homework.shownCount", { count: items.length, label: visibleLabel })}</p><p className="swipe-hint">{t("homework.swipeHint")}</p></div><div id="list">{items.map((task) => <article className={`hw card ${task.status === "überfällig" ? "st-ueber" : task.status === "heute fällig" ? "st-heute" : task.is_done ? "st-erledigt" : "st-offen"}${task.is_done ? " is-done" : ""}${task.is_hidden ? " is-hidden" : ""}`} key={task.id}><h3>{task.title}</h3><div className="meta"><span className="tag tag-muted">{task.type_label ?? task.type}</span><span className="tag tag-blue">{homeworkStatusPill(task.status)}</span>{task.is_hidden && <span className="tag tag-gray">{t("homework.deleted")}</span>}<span>{t("homework.dueLabel")} <strong>{task.due_display}</strong></span><span>{t("homework.assignedLabel")} {task.assigned ?? task.assigned_iso ?? "–"}</span>{task.subject && <span>{task.subject}</span>}<span>{task.teacher || task.author || ""}</span>{task.is_starred && <span className="tag tag-soft">{t("homework.starred")}</span>}{task.done_at && <span className="tag tag-soft">✓ {task.done_at}</span>}</div><div className="text">{task.description?.trim() || t("common.noDescription")}</div><div className="hw-actions"><button className={`btn ${task.is_done ? "btn-light" : "btn-primary"} btn-sm`} type="button" onClick={() => void change(task, task.is_hidden ? "trash" : "done")}>{task.is_hidden ? t("homework.restore") : task.is_done ? t("homework.reopen") : t("homework.doneBtn")}</button>{!task.is_hidden && <button className="btn btn-light btn-sm" type="button" onClick={() => void change(task, "trash")}>{t("homework.trashLabel")}</button>}</div></article>)}</div>{!items.length && <Empty>{status === "papierkorb" ? t("homework.trashEmpty") : t("homework.empty")}</Empty>}</div></div>
  </>;
}

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

function GradesView() {
  const [grades, setGrades] = useState<Grade[]>([]); const [error, setError] = useState(""); const [refreshing, setRefreshing] = useState(false); const [term, setTerm] = useState(currentGradeTerm()); const [query, setQuery] = useState("");
  async function load(refresh = false) { setRefreshing(refresh); try { const result = await api<Page<Grade>>(`/grades?limit=200${refresh ? "&refresh=1" : ""}`); setGrades(result.items); setError(""); } catch (e) { setError((e as Error).message); } finally { setRefreshing(false); } }
  useEffect(() => { void load(); }, []);
  const terms = useMemo(() => Array.from(new Set(grades.map((grade) => gradeTerm(grade.date_iso)))).sort((a, b) => b.localeCompare(a)), [grades]);
  useEffect(() => { if (terms.length && !terms.includes(term)) setTerm(terms[0]); }, [term, terms]);
  const inTerm = useMemo(() => grades.filter((grade) => gradeTerm(grade.date_iso) === term), [grades, term]);
  const normalizedQuery = query.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag()).trim();
  const groups = useMemo(() => inTerm.filter((grade) => !normalizedQuery || [grade.subject, grade.title, grade.teacher].join(" ").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase(localeTag()).includes(normalizedQuery)).reduce<Record<string, Grade[]>>((result, grade) => { (result[grade.subject] ??= []).push(grade); return result; }, {}), [inTerm, normalizedQuery]);
  return <><PageTitle eyebrow={t("grades.eyebrow")} title={t("nav.grades")} detail={t("grades.detailCount", { count: inTerm.length, avg: weightedAverage(inTerm) })} /><Notice error={error} />
    <div className="grades-bar anim-in"><div className="view-toggle" role="tablist" aria-label={t("grades.halfYearAria")}>{terms.map((key) => <button type="button" role="tab" aria-selected={term === key} className={term === key ? "active" : ""} key={key} onClick={() => setTerm(key)}>{gradeTermLabel(key)} ({grades.filter((grade) => gradeTerm(grade.date_iso) === key).length})</button>)}</div><div className="grades-tools"><div className="search-field grades-search"><input className="input-pill" type="search" aria-label={t("grades.searchAria")} placeholder={t("grades.searchPlaceholder")} value={query} onChange={(event) => setQuery(event.target.value)} /></div><button className="btn btn-light btn-sm" disabled={refreshing} onClick={() => void load(true)}>{refreshing ? t("common.loading") : t("grades.refresh")}</button></div></div>
    {Object.entries(groups).map(([subject, rows]) => <section className="subj card anim-in" key={subject}><div className="subj-head"><div className="subj-title"><h3>{subject}</h3><div className="meta">{rows.length} {rows.length === 1 ? t("grades.noteOne") : t("nav.grades")}</div></div><div className={`subj-avg ${weightedAverage(rows) === "–" ? "subj-avg-none" : ""}`} title={t("grades.avgTitle")}>Ø {weightedAverage(rows)}</div></div><div className="chips">{rows.map((grade) => <span className={`chip ${grade.badge}`} key={grade.id} title={`${grade.title} · ${grade.date_display}${grade.weight_display ? ` · ${t("grades.colWeight")} ${grade.weight_display}` : ""}`}>{grade.grade_display}{grade.weight_display && <small>{grade.weight_display}</small>}</span>)}</div><details><summary>{t("grades.details")}</summary><div className="tt-scroll"><table className="g-table"><thead><tr><th>{t("grades.colDate")}</th><th>{t("grades.colTopic")}</th><th>{t("grades.noteOne")}</th><th>{t("grades.colWeight")}</th><th>{t("grades.colTeacher")}</th><th>{t("grades.colClassAvg")}</th><th>{t("grades.colComment")}</th></tr></thead><tbody>{rows.map((grade) => <tr key={grade.id}><td className="nowrap">{grade.date_display}</td><td>{grade.title}</td><td><strong>{grade.grade_display}</strong>{grade.grade_sub && <span className="dim"> · {grade.grade_sub}</span>}</td><td className="nowrap">{grade.weight_display || t("grades.weightOnce")}</td><td>{grade.teacher || "–"}</td><td className="nowrap">{grade.class_avg_display || "–"}</td><td>{grade.comment || "–"}</td></tr>)}</tbody></table></div></details></section>)}
    {!Object.keys(groups).length && !error && <Empty>{grades.length ? t("grades.emptyFiltered") : t("grades.empty")}</Empty>}</>;
}

function TimetableView() {
  type TimetableData = { day_label?: string; lessons?: Lesson[]; week_label?: string; days?: Array<{ date: string; day_name: string; day_date: string; is_today?: boolean; lessons: Lesson[] }> };
  type Substitution = { date: string; day_label: string; changes: Array<{ class?: string; lesson: string; title: string; action: string }> };
  const [day, setDay] = useState(new Date().toISOString().slice(0, 10)); const [mode, setMode] = useState<"week" | "day">("week"); const [data, setData] = useState<TimetableData | null>(null); const [substitutions, setSubstitutions] = useState<Substitution[]>([]); const [error, setError] = useState("");
  useEffect(() => { let live = true; Promise.all([api<TimetableData>(`/timetable/${mode}?day=${day}`), api<{ days: Substitution[] }>(`/substitutions/week?day=${day}`)]).then(([schedule, changes]) => { if (live) { setData(schedule); setSubstitutions(changes.days); setError(""); } }).catch((e: Error) => { if (live) setError(e.message); }); return () => { live = false; }; }, [day, mode]);
  function addDay(change: number) { const d = new Date(`${day}T12:00:00`); d.setDate(d.getDate() + change); setDay(d.toISOString().slice(0, 10)); }
  function periodRange(lesson: Lesson) { const numbers = (lesson.period.match(/\d+/g) ?? []).map(Number); return { first: numbers[0] ?? 0, last: numbers[1] ?? numbers[0] ?? 0 }; }
  const week = data?.days ?? [];
  const periods = Array.from(new Set(week.flatMap((item) => item.lessons.filter((lesson) => !lesson.is_event).flatMap((lesson) => { const range = periodRange(lesson); return range.first ? Array.from({ length: range.last - range.first + 1 }, (_, i) => range.first + i) : []; })))).sort((a, b) => a - b);
  const cells = new Map<string, Lesson>(); const covered = new Set<string>();
  for (const item of week) for (const lesson of item.lessons) { const range = periodRange(lesson); if (!range.first) continue; cells.set(`${item.date}-${range.first}`, lesson); for (let period = range.first + 1; period <= range.last; period++) covered.add(`${item.date}-${period}`); }
  const lessonCards = (items: Lesson[]) => items.map((lesson, index) => <article className={`lesson card${lesson.is_cancelled ? " is-cancelled" : ""}${lesson.is_event ? " is-event" : ""}`} key={`${lesson.period}-${index}`}><div className="lesson-time">{lesson.time}</div><div className="lesson-main"><h3>{lesson.title}</h3><div className="meta">{lesson.is_cancelled && <span className="tag tag-red">{t("overview.cancelled")}</span>}{lesson.is_event && <span className="tag tag-amber">{t("timetable.eventTag")}</span>}{lesson.is_online && <span className="tag tag-blue">{t("timetable.onlineTag")}</span>}{lesson.teachers && <span>{lesson.teachers}</span>}{lesson.rooms && <span>{t("overview.room", { rooms: lesson.rooms })}</span>}</div></div></article>);
  const substitutionAction = (action: string) => action === "remove" ? t("overview.cancelled") : action === "add" ? t("agenda.actionAdd") : t("agenda.actionChange");
  return <><PageTitle eyebrow={t("timetable.eyebrow")} title={mode === "week" ? data?.week_label ?? t("nav.timetable") : data?.day_label ?? t("nav.timetable")} detail={mode === "week" ? t("timetable.weekDetail", { count: week.reduce((total, item) => total + item.lessons.length, 0) }) : t("timetable.dayDetail", { count: (data?.lessons ?? []).length })} /><Notice error={error} />
    <div className="schedule-toolbar"><div className="view-toggle" role="tablist" aria-label={t("timetable.viewAria")}><button type="button" role="tab" aria-selected={mode === "day"} className={mode === "day" ? "active" : ""} onClick={() => setMode("day")}>{t("timetable.dayTab")}</button><button type="button" role="tab" aria-selected={mode === "week"} className={mode === "week" ? "active" : ""} onClick={() => setMode("week")}>{t("agenda.weekLabel")}</button></div>{mode === "day" ? <div className="day-nav"><button className="btn btn-light btn-sm" onClick={() => addDay(-1)}>{t("timetable.backDay")}</button><div className="field"><label htmlFor="timetable-day">{t("timetable.dayTab")}</label><input className="input-pill" id="timetable-day" type="date" value={day} onChange={(event) => setDay(event.target.value)} /></div><button className="btn btn-light btn-sm" onClick={() => setDay(new Date().toISOString().slice(0, 10))}>{t("overview.today")}</button><button className="btn btn-light btn-sm" onClick={() => addDay(1)}>{t("timetable.nextDay")}</button></div> : <div className="day-nav"><button className="btn btn-light btn-sm" onClick={() => addDay(-7)}>{t("agenda.prevWeek")}</button><button className="btn btn-light btn-sm" onClick={() => setDay(new Date().toISOString().slice(0, 10))}>{t("agenda.thisWeek")}</button><button className="btn btn-light btn-sm" onClick={() => addDay(7)}>{t("agenda.nextWeek")}</button></div>}</div>
    {mode === "week" ? <div className="tt-scroll"><div className="tt-matrix anim-in"><div style={{ gridColumn: 1, gridRow: 1 }} />{week.map((item, index) => <div className="tt-day" style={{ gridColumn: index + 2, gridRow: 1 }} key={item.date}>{item.day_name}<small>{item.day_date}</small>{item.is_today && <span className="tag tag-solid">{t("timetable.todayTag")}</span>}</div>)}{periods.map((period, index) => <Fragment key={period}><div className="tt-period" style={{ gridColumn: 1, gridRow: index + 2 }}>{period}.</div>{week.map((item, dayIndex) => { const lesson = cells.get(`${item.date}-${period}`); const range = lesson ? periodRange(lesson) : { first: period, last: period }; if (covered.has(`${item.date}-${period}`)) return null; return <div className={`tt-cell${lesson?.is_cancelled ? " is-cancelled" : ""}${lesson?.is_event ? " is-event" : ""}`} style={{ gridColumn: dayIndex + 2, gridRow: `${index + 2}${range.last > range.first ? ` / span ${range.last - range.first + 1}` : ""}` }} key={`${item.date}-${period}`}>{lesson ? <><strong>{lesson.title}</strong><small>{lesson.rooms ? t("overview.room", { rooms: lesson.rooms }) : ""}{lesson.rooms && lesson.teachers ? " · " : ""}{lesson.teachers}{lesson.time && !lesson.is_lernzeit && !lesson.is_event ? `${lesson.rooms || lesson.teachers ? " · " : ""}${lesson.time}` : ""}</small>{lesson.is_cancelled && <span className="tag tag-red">{t("timetable.cancelledSmall")}</span>}</> : <span className="tt-empty">–</span>}</div>; })}</Fragment>)}</div></div> : <div id="list">{lessonCards(data?.lessons ?? [])}{!data?.lessons?.length && <Empty>{t("timetable.emptyDay")}</Empty>}</div>}
    <section className="agenda-section timetable-substitutions"><h2>{t("agenda.subsTitle")}</h2>{substitutions.some((entry) => entry.changes.length) ? substitutions.map((entry) => entry.changes.map((change, index) => <div className="agenda-day" key={`${entry.date}-${index}`}><h3>{entry.day_label}</h3><article className="card agenda-change"><span className="agenda-period">{t("timetable.lessonHour", { lesson: change.lesson })}</span><div><strong>{change.title}</strong><p className="agenda-meta">{change.class ? t("agenda.classLabel", { cls: change.class }) : t("agenda.planChange")}</p></div><span className={`tag ${change.action === "remove" ? "tag-red" : change.action === "add" ? "tag-blue" : "tag-amber"}`}>{substitutionAction(change.action)}</span></article></div>)) : <div className="card agenda-empty">{t("agenda.emptySubs")}</div>}</section>
  </>;
}

function AgendaView() {
  const today = new Date().toISOString().slice(0, 10); const [day, setDay] = useState(today); const [items, setItems] = useState<AgendaItem[]>([]); const [substitutions, setSubstitutions] = useState<Array<{ date: string; day_label: string; changes: Array<{ class?: string; lesson: string; title: string; action: string }> }>>([]); const [weekLabel, setWeekLabel] = useState(""); const [error, setError] = useState(""); const [loading, setLoading] = useState(true); const [refreshKey, setRefreshKey] = useState(0);
  const bounds = useMemo(() => { const selected = new Date(`${day}T12:00:00`); const start = new Date(selected); const end = new Date(selected); start.setDate(selected.getDate() - 30); end.setDate(selected.getDate() + 60); return { from: start.toISOString().slice(0, 10), until: end.toISOString().slice(0, 10) }; }, [day]);
  useEffect(() => { let live = true; setLoading(true); const params = new URLSearchParams({ since: bounds.from, until: bounds.until }); if (refreshKey) params.set("refresh", "1"); Promise.all([api<{ items: AgendaItem[] }>(`/school/agenda?${params}`), api<{ week_label: string; days: typeof substitutions }>(`/substitutions/week?day=${day}`)]).then(([calendar, changes]) => { if (!live) return; setItems(calendar.items); setSubstitutions(changes.days); setWeekLabel(changes.week_label); setError(""); }).catch((e: Error) => { if (live) setError(e.message); }).finally(() => { if (live) setLoading(false); }); return () => { live = false; }; }, [bounds.from, bounds.until, day, refreshKey]);
  function addWeek(amount: number) { const date = new Date(`${day}T12:00:00`); date.setDate(date.getDate() + amount * 7); setDay(date.toISOString().slice(0, 10)); }
  const labels: Record<string, string> = { event: t("agenda.kindEvent"), exam: t("agenda.kindExam"), attendance: t("agenda.kindAttendance") };
  return <><PageTitle eyebrow={t("agenda.eyebrow")} title={t("agenda.title")} detail={weekLabel || t("agenda.detailFallback")} /><Notice error={error} /><form className="day-nav" onSubmit={(event) => { event.preventDefault(); setRefreshKey((key) => key + 1); }}><button className="btn btn-light btn-sm" type="button" onClick={() => addWeek(-1)}>{t("agenda.prevWeek")}</button><div className="field"><label htmlFor="agenda-day">{t("agenda.weekLabel")}</label><input className="input-pill" id="agenda-day" type="date" value={day} onChange={(event) => setDay(event.target.value)} /></div><button className="btn btn-light btn-sm" type="button" onClick={() => setDay(today)}>{t("agenda.thisWeek")}</button><button className="btn btn-light btn-sm" type="button" onClick={() => addWeek(1)}>{t("agenda.nextWeek")}</button><button className="btn btn-primary btn-sm" type="submit">{t("agenda.refresh")}</button></form>
    <div className="agenda-sections"><section className="agenda-section" aria-labelledby="agenda-heading"><h2 id="agenda-heading">{t("agenda.calTitle")}</h2>{items.map((item) => <article className="card agenda-row" key={item.id}><time>{formatDate(item.date)}</time><span className={`tag tag-${item.kind}`}>{labels[item.kind] ?? item.kind}</span><div><strong>{item.title ?? item.text}</strong>{item.subject && <p className="agenda-meta">{item.subject}</p>}</div></article>)}{!items.length && !loading && <div className="card agenda-empty">{t("agenda.emptyCal")}</div>}</section>
      <section className="agenda-section" aria-labelledby="substitution-heading"><h2 id="substitution-heading">{t("agenda.subsTitle")}</h2>{substitutions.some((entry) => entry.changes.length) ? substitutions.map((entry) => entry.changes.map((change, index) => <div className="agenda-day" key={`${entry.date}-${index}`}><h3>{entry.day_label}</h3><article className="card agenda-change"><span className="agenda-period">{t("timetable.lessonHour", { lesson: change.lesson })}</span><div><strong>{change.title}</strong><p className="agenda-meta">{change.class ? t("agenda.classLabel", { cls: change.class }) : t("agenda.planChange")}</p></div><span className={`tag ${change.action === "remove" ? "tag-red" : change.action === "add" ? "tag-blue" : "tag-amber"}`}>{change.action === "remove" ? t("overview.cancelled") : change.action === "add" ? t("agenda.actionAdd") : t("agenda.actionChange")}</span></article></div>)) : !loading && <div className="card agenda-empty">{t("agenda.emptySubs")}</div>}</section></div>{loading && <p className="muted" aria-live="polite">{t("agenda.loadingCal")}</p>}</>;
}

function SettingsView() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [devices, setDevices] = useState<Array<{ id: string; device: string; created: string; expires: string; short?: string; current?: boolean; revoked?: boolean }>>([]);
  const [error, setError] = useState(""); const [feedback, setFeedback] = useState(""); const [busy, setBusy] = useState(false);
  const [deviceName, setDeviceName] = useState(""); const [newToken, setNewToken] = useState<{ token: string; refresh_token?: string; expires: string; device: string } | null>(null);
  const [themeChoice, setThemeChoice] = useState("system"); const [accent, setAccent] = useState("black");
  const [order, setOrder] = useState("messages,homework,weather");
  const [layout, setLayout] = useState<SectionLayout>({ order: SECTION_KEYS.slice(), hidden: [] });
  const layoutOrder = normalizeOrder({ ov_order: layout.order.join(",") });
  const layoutHidden = layout.hidden;
  const sectionHints = { drag: t("overview.editorDrag"), up: t("settings.moveUp"), down: t("settings.moveDown"), hide: t("overview.editorHide"), show: t("overview.editorShow"), hidden: t("overview.editorHidden") };
  const [cityValue, setCityValue] = useState(""); const [cityQuery, setCityQuery] = useState("");
  const [cityOptions, setCityOptions] = useState<Array<{ name: string; country?: string }>>([]); const [cityStatus, setCityStatus] = useState("");
  const load = useCallback(async () => {
    try {
      const [nextSettings, nextDevices] = await Promise.all([api<Settings>("/settings"), api<{ items: typeof devices }>("/devices")]);
      setSettings(nextSettings); setDevices(nextDevices.items); setError("");
      setOrder(String(nextSettings.values.ov_order ?? "messages,homework,weather"));
      setLayout({ order: normalizeOrder(nextSettings.values), hidden: normalizeHidden(nextSettings.values) });
      setCityValue(String(nextSettings.values.wetter_city ?? ""));
    } catch (e) { setError((e as Error).message); }
  }, []);
  useEffect(() => { void load(); setThemeChoice(window.EduFlowTheme?.choice() ?? "system"); setAccent(window.EduFlowTheme?.accent() ?? "black"); }, [load]);
  useEffect(() => {
    const query = cityQuery.trim();
    if (query.length < 2) { setCityOptions([]); setCityStatus(""); return; }
    let live = true;
    setCityStatus(t("settings.searchingCities"));
    const timer = window.setTimeout(() => {
      void api<{ items: Array<{ name: string; country?: string }> }>(`/wetter/suche?q=${encodeURIComponent(query)}`)
        .then((result) => { if (live) { setCityOptions(result.items); setCityStatus(result.items.length ? "" : t("settings.noCities")); } })
        .catch(() => { if (live) setCityStatus(t("settings.citySearchFailed")); });
    }, 280);
    return () => { live = false; window.clearTimeout(timer); };
  }, [cityQuery]);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!settings) return; setBusy(true);
    const form = new FormData(event.currentTarget); const payload: Record<string, unknown> = {};
    for (const item of settings.schema) {
      if (item.kind === "bool") payload[item.key] = form.has(item.key);
      else if (item.kind === "int") payload[item.key] = Number(form.get(item.key));
      else payload[item.key] = form.get(item.key);
    }
    try {
      const result = await api<{ values: Record<string, unknown> }>("/settings", { method: "PUT", body: JSON.stringify(payload) });
      setSettings({ ...settings, values: result.values }); setOrder(String(result.values.ov_order ?? order)); setLayout({ order: normalizeOrder(result.values), hidden: normalizeHidden(result.values) }); setCityValue(String(result.values.wetter_city ?? "")); setFeedback(t("settings.saved")); setError("");
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  async function revoke(id: string) { try { await api(`/devices/${id}`, { method: "DELETE" }); await load(); setFeedback(t("settings.revoked")); } catch (e) { setError((e as Error).message); } }
  async function createDeviceToken(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(""); setFeedback("");
    try {
      const result = await api<{ token: string; refresh_token?: string; expires: string; device?: string; username?: string }>("/devices", { method: "POST", body: JSON.stringify({ device: deviceName }) });
      setNewToken({ token: result.token, refresh_token: result.refresh_token, expires: result.expires, device: deviceName.trim() || t("settings.unnamedDevice") });
      setDeviceName(""); await load(); setFeedback(t("settings.tokenCreated"));
    } catch (e) { setError((e as Error).message); } finally { setBusy(false); }
  }
  async function copyToken(value: string, label: string) {
    try { await navigator.clipboard.writeText(value); setFeedback(t("settings.copiedToClipboard", { label })); }
    catch { setError(t("settings.copyFailed")); }
  }
  async function clearCache() { try { const result = await api<{ cleared: number }>("/cache-clear", { method: "POST" }); setFeedback(t("settings.cacheCleared", { count: result.cleared })); } catch (e) { setError((e as Error).message); } }
  const orderLabels: Record<string, string> = { messages: t("nav.messages"), homework: t("nav.homework"), weather: t("overview.weather") };
  const accents = [["black", t("settings.accentBlack"), "#000000"], ["blue", t("settings.accentBlue"), "#2563EB"], ["violet", t("settings.accentViolet"), "#7C3AED"], ["teal", t("settings.accentTeal"), "#0E7490"], ["green", t("settings.accentGreen"), "#16A34A"], ["orange", t("settings.accentOrange"), "#EA580C"], ["red", t("settings.accentRed"), "#DC2626"], ["pink", t("settings.accentPink"), "#DB2777"]];
  return <><PageTitle eyebrow={t("settings.eyebrow")} title={t("nav.settings")} detail={t("settings.detail")} /><Notice error={error} /><p className="notice-success" aria-live="polite">{feedback}</p>
    <section className="panel" aria-labelledby="set-look"><h2 className="set-title" id="set-look">{t("settings.lookTitle")}</h2><p className="set-note">{t("settings.lookNote")}</p><h3 className="set-sub">{t("settings.colorScheme")}</h3><div className="radio-cards" role="radiogroup" aria-label={t("settings.colorScheme")}>{[["system", t("settings.schemeSystem"), t("settings.schemeSystemHint")], ["light", t("settings.schemeLight"), t("settings.schemeLightHint")], ["dark", t("settings.schemeDark"), t("settings.schemeDarkHint")]].map(([value, label, hint]) => <label className="radio-card" key={value}><input type="radio" name="theme-choice" value={value} checked={themeChoice === value} onChange={() => { setThemeChoice(value); window.EduFlowTheme?.setChoice(value); setFeedback(t("settings.schemeApplied")); }} /><span className="rc-body"><span className="rc-t">{label}</span><span className="rc-d">{hint}</span></span></label>)}</div><h3 className="set-sub">{t("settings.accentTitle")}</h3><div className="accent-dots set-accents" role="group" aria-label={t("settings.accentTitle")}>{accents.map(([key, label, color]) => <button className={`accent-dot ${accent === key ? "active" : ""}`} key={key} type="button" data-set-accent={key} aria-label={label} aria-pressed={accent === key} title={label} style={{ "--c": color } as React.CSSProperties} onClick={() => { setAccent(key); window.EduFlowTheme?.setAccent(key); setFeedback(t("settings.accentApplied")); }} />)}</div><h3 className="set-sub">{t("settings.languageTitle")}</h3><LanguagePicker className="lang-block" /><div className="field-hint">{t("settings.languageHint")}</div></section>
    {settings && <form className="panel settings-form" onSubmit={save} aria-labelledby="set-general"><h2 className="set-title" id="set-general">{t("settings.generalTitle")}</h2><p className="set-note">{t("settings.generalNote")}</p><input type="hidden" name="ov_order" value={layoutOrder.join(",")} /><input type="hidden" name="ov_hidden" value={layoutHidden.join(",")} />{settings.schema.map((item, index) => <Fragment key={item.key}>{item.section && settings.schema[index - 1]?.section !== item.section && <h3 className="set-sub">{item.section}</h3>}{item.kind === "bool" ? item.key === "ov_wetter" ? <label className="setting-switch" htmlFor={`set-${item.key}`}><span className="setting-switch-copy"><span className="setting-switch-title">{item.label}</span><span className="setting-switch-hint">{item.hint ?? ""}</span></span><input className="setting-switch-input" id={`set-${item.key}`} type="checkbox" name={item.key} defaultChecked={settings.values[item.key] === true} /><span className="setting-switch-track" aria-hidden="true"><span /></span></label> : <label className="check"><input type="checkbox" name={item.key} defaultChecked={settings.values[item.key] === true} /> {item.label}</label> : item.kind === "select" ? <div className="field"><label id={`set-${item.key}-label`}>{item.label}</label><Select labelledBy={`set-${item.key}-label`} name={item.key} testId={`set-${item.key}`} defaultValue={String(settings.values[item.key] ?? item.default)} options={(item.options ?? []).map(([value, label]) => ({ value, label }))} /></div> : item.kind === "int" ? <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><input className="input-pill" id={`set-${item.key}`} type="number" name={item.key} min={item.min} max={item.max} step={1} defaultValue={Number(settings.values[item.key] ?? item.default)} />{item.hint && <div className="field-hint">{item.hint}</div>}</div> : item.kind === "order" ? <div className="field"><label>{item.label}</label><SectionEditor layout={{ order: layoutOrder, hidden: layoutHidden }} labels={orderLabels} hints={sectionHints} onChange={setLayout} /><div className="field-hint">{t("settings.orderHint")}</div></div>: item.kind === "hidden" ? <div className="field"><label>{item.label}</label>{item.hint && <div className="field-hint">{item.hint}</div>}</div> : item.key === "wetter_city" ? <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><div className="weather-city-search"><input className="input-pill" id={`set-${item.key}`} type="text" name={item.key} value={cityValue} maxLength={item.maxlength ?? 100} placeholder={item.placeholder ?? t("settings.cityPlaceholder")} autoComplete="off" role="combobox" aria-autocomplete="list" aria-expanded={Boolean(cityQuery && (cityOptions.length || cityStatus))} aria-controls="weather-city-options" onChange={(event) => { setCityValue(event.target.value); setCityQuery(event.target.value); }} onKeyDown={(event) => { if (event.key === "Escape") { setCityQuery(""); setCityOptions([]); } if (event.key === "Enter" && cityOptions.length) { event.preventDefault(); setCityValue(cityOptions[0].name); setCityQuery(""); setCityOptions([]); } }} /><div className="weather-city-options" id="weather-city-options" role="listbox" hidden={!cityQuery || (!cityOptions.length && !cityStatus)}>{cityStatus && <div className="weather-city-status" role="status">{cityStatus}</div>}{cityOptions.map((option) => <button className="weather-city-option" type="button" role="option" key={`${option.name}-${option.country}`} onClick={() => { setCityValue(option.name); setCityQuery(""); setCityOptions([]); }}><span className="weather-city-option-title">{option.name}</span>{option.country && <span className="weather-city-option-detail">{option.country}</span>}</button>)}</div></div>{item.hint && <div className="field-hint">{item.hint}</div>}</div> : <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><input className="input-pill" id={`set-${item.key}`} name={item.key} maxLength={item.maxlength} defaultValue={String(settings.values[item.key] ?? item.default ?? "")} placeholder={item.placeholder} />{item.hint && <div className="field-hint">{item.hint}</div>}</div>}</Fragment>)}<div><button className="btn btn-primary" disabled={busy}><Icon name="save" />{busy ? t("settings.saving") : t("settings.save")}</button></div></form>}
    <section className="panel"><div className="panel-heading"><div><p className="eyebrow">{t("settings.sessionsEyebrow")}</p><h2>{t("settings.devicesTitle")}</h2></div></div>{devices.map((device) => <div className="device-row" key={device.id}><div><strong>{device.device || t("settings.unnamedDevice")}{device.current ? t("settings.thisDevice") : ""}</strong><span>{t("settings.loggedInAt", { created: formatDate(device.created), expires: formatDate(device.expires) })}</span></div>{!device.revoked && !device.current && <button className="secondary" type="button" onClick={() => void revoke(device.id)}><Icon name="logout" />{t("nav.logout")}</button>}</div>)}{!devices.length && <Empty>{t("settings.noDevices")}</Empty>}</section>
    <section className="panel" aria-labelledby="set-api"><h2 className="set-title" id="set-api">{t("settings.apiTitle")}</h2><p className="set-note">{t("settings.apiNote")}</p>
      <form className="device-token-form" onSubmit={(event) => void createDeviceToken(event)}><div className="field"><label htmlFor="api-device">{t("settings.deviceNameLabel")}</label><input className="input-pill" id="api-device" value={deviceName} onChange={(event) => setDeviceName(event.target.value)} placeholder={t("settings.deviceNamePlaceholder")} maxLength={80} autoComplete="off" /></div><button className="btn btn-primary" type="submit" disabled={busy}><Icon name="key" />{busy ? t("settings.creating") : t("settings.createToken")}</button></form>
      {newToken && <div className="new-token-result" role="status"><p className="notice"><strong>{t("settings.newTokenFor", { device: newToken.device })}</strong></p><div className="token-box"><span>{t("settings.accessLabel")}</span><code>{newToken.token}</code><button className="btn btn-light btn-sm" type="button" onClick={() => void copyToken(newToken.token, t("settings.accessTokenLabel"))}><Icon name="copy" />{t("settings.copy")}</button></div>{newToken.refresh_token && <div className="token-box"><span>{t("settings.refreshLabel")}</span><code>{newToken.refresh_token}</code><button className="btn btn-light btn-sm" type="button" onClick={() => void copyToken(newToken.refresh_token ?? "", t("settings.refreshTokenLabel"))}>{t("settings.copy")}</button></div>}<p className="set-note">{t("settings.validUntil", { date: formatDate(newToken.expires) })} {newToken.refresh_token ? t("settings.storeBoth") : t("settings.storeOne")} {t("settings.storeHint")}</p></div>}
    </section>
    <section className="panel"><h2 className="set-title">{t("settings.dataTitle")}</h2><p className="set-note">{t("settings.dataNote")}</p><button className="btn btn-light" type="button" onClick={() => void clearCache()}><Icon name="trash" />{t("settings.clearCache")}</button></section>
  </>;
}
