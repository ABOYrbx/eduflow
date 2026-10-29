"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { localeTag, t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";
import { Icon } from "./icon";
import { SessionsView } from "./sessions-view";
import { Notice } from "./ui";
import { AgendaView } from "./views/agenda-view";
import { GradesView } from "./views/grades-view";
import { HomeworkView } from "./views/homework-view";
import { MessagesView } from "./views/messages-view";
import { OverviewView } from "./views/overview-view";
import { SettingsView } from "./views/settings-view";
import { TimetableView } from "./views/timetable-view";

/** Navigation — bewusst als Funktion, damit `t()` erst beim Rendern liest
 *  und ein Sprachwechsel die Beschreibungen mitnimmt. */
const nav = () => [{ href: "/", label: t("nav.overview") }, { href: "/messages", label: t("nav.messages") }, { href: "/homework", label: t("nav.homework") }, { href: "/grades", label: t("nav.grades") }, { href: "/timetable", label: t("nav.timetable") }, { href: "/agenda", label: t("nav.agenda") }];

/**
 * Rahmen der Web-UI: Kopfleiste, Navigation und die Auswahl der Ansicht
 * über den Pfad. Die Seiten selbst liegen in `views/*`, die Wire-Typen in
 * `lib/types.ts`, der Datenweg in `lib/api.ts`, die Formatierer in
 * `lib/format.ts`.
 */
export function DashboardApp({ username }: { username: string }) {
  const path = usePathname(); const router = useRouter();
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const items = nav();
  const active = path === "/mehr" ? "Mehr" : path === "/sessions" ? t("nav.sessions") : items.find((item) => item.href === path)?.label ?? t("nav.settings");
  const [logoutError, setLogoutError] = useState("");
  const navRef = useRef<HTMLElement>(null);
  const [navEdges, setNavEdges] = useState({ start: false, end: false });
  useEffect(() => {
    if (!navRef.current) return;
    const el: HTMLElement = navRef.current;
    const update = () => setNavEdges({ start: el.scrollLeft > 4, end: el.scrollLeft + el.clientWidth < el.scrollWidth - 4 });
    update();
    el.addEventListener("scroll", update, { passive: true });
    const observer = new ResizeObserver(update);
    observer.observe(el);
    window.addEventListener("resize", update);
    // Senkrechtes Mausrad waagerecht ausgeben. Bewusst nativ und
    // nicht-passiv: React haengt wheel passiv am Root an, dann greift
    // preventDefault nicht. Nur wenn sich die Leiste wirklich bewegt hat,
    // wird die Seite nicht weitergescrollt.
    function onWheel(event: WheelEvent) {
      if (el.scrollWidth <= el.clientWidth + 1) return;
      const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
      if (delta === 0) return;
      const before = el.scrollLeft;
      el.scrollLeft = before + delta;
      if (el.scrollLeft !== before) event.preventDefault();
    }
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => {
      el.removeEventListener("scroll", update);
      el.removeEventListener("wheel", onWheel);
      observer.disconnect();
      window.removeEventListener("resize", update);
    };
  }, []);
  function scrollNav(direction: -1 | 1) {
    const el = navRef.current;
    if (!el) return;
    const pill = el.querySelector<HTMLElement>(".nav-pill");
    // scrollLeft direkt setzen statt scrollBy mit Verhalten: die
    // Options-Form wird nicht ueberall animiert und blieb dort wirkungslos.
    // Die weiche Bewegung kommt aus scroll-behavior in der CSS-Datei.
    const step = (pill ? pill.offsetWidth + 2 : 120) * 2;
    el.scrollLeft = Math.max(0, Math.min(el.scrollWidth - el.clientWidth, el.scrollLeft + direction * step));
  }
  async function logout() { const response = await fetch("/api/auth/logout", { method: "POST" }); if (response.ok) router.replace("/login"); else setLogoutError(t("nav.logoutFailed")); }
  return <>
    <div className={`nav-wrap${navEdges.start ? " has-start" : ""}${navEdges.end ? " has-end" : ""}`}><div className="container nav">
      <Link className="nav-logo" href="/" aria-label={t("nav.logoAria")}><img src="/icons/icon.png" alt="" /></Link>
      {navEdges.start && <button className="nav-scroll nav-scroll-start" type="button" aria-label={t("nav.scrollBack")} onClick={() => scrollNav(-1)}><Icon name="left" /></button>}
      <nav className="nav-mid" aria-label={t("nav.mainAria")} ref={navRef}>{items.map((item) => <Link className={`nav-pill ${active === item.label ? "active" : ""}`} key={item.href} href={item.href}>{item.label}</Link>)}</nav>
      {navEdges.end && <button className="nav-scroll nav-scroll-end" type="button" aria-label={t("nav.scrollForward")} onClick={() => scrollNav(1)}><Icon name="right" /></button>}
      <div className="nav-cta"><div className="profile-wrap">
        <button className="avatar-btn" type="button" aria-haspopup="true" aria-expanded="false" aria-label={t("nav.profileAria")} title={username}>{username.slice(0, 1).toLocaleUpperCase(localeTag())}</button>
        <div className="profile-menu" role="menu"><div className="pm-head"><div className="t">{t("nav.profileTitle")}</div><div className="u">{username}</div></div><div className="pm-div" />
          <Link className="pm-link" href="/settings" role="menuitem"><Icon name="gear" />{t("nav.settings")}</Link>
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
      {path === "/sessions" && <SessionsView />}
      {(path === "/settings" || path === "/mehr") && <SettingsView />}
      <footer><p>{t("nav.footer")}</p></footer>
    </main>
  </>;
}
