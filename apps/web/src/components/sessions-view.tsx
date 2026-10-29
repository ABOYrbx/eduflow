"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { localeTag, t } from "../lib/i18n";
import { useLocale } from "../lib/locale-context";
import { api } from "../lib/api";
import type { Device } from "../lib/types";
import { Icon } from "./icon";
import { Empty, Notice, PageTitle } from "./ui";
import { SearchField } from "./search-field";

function stamp(value: string, locale: string, options: Intl.DateTimeFormatOptions): string {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleString(locale, options);
}

/**
 * Eigene Seite für die angemeldeten Geräte: suchen, einzeln abmelden oder
 * alle anderen auf einmal. Bewusst als Seite und nicht als weiteres Panel in
 * den Einstellungen — die Liste kann lang werden und soll nicht die
 * Einstellungen aufblähen.
 */
export function SessionsView() {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const [devices, setDevices] = useState<Device[]>([]);
  const [error, setError] = useState("");
  const [feedback, setFeedback] = useState("");
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  async function load() {
    try {
      const page = await api<{ items: Device[] }>("/devices");
      setDevices(page.items);
      setError("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, []);

  async function revoke(id: string) {
    setBusy(true); setFeedback("");
    try {
      await api(`/devices/${encodeURIComponent(id)}`, { method: "DELETE" });
      await load();
      setFeedback(t("settings.revoked"));
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }

  async function revokeOthers() {
    setBusy(true); setFeedback("");
    try {
      const result = await api<{ revoked: number }>("/devices/revoke-others", { method: "POST" });
      await load();
      setFeedback(result.revoked > 0 ? t("sessions.revokedOthers", { count: result.revoked }) : t("sessions.noOthers"));
    } catch (e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }

  const needle = query.trim().toLowerCase();
  const visible = needle
    ? devices.filter((item) => `${item.device} ${item.short ?? ""} ${item.id}`.toLowerCase().includes(needle))
    : devices;
  const otherActive = devices.filter((item) => !item.current && !item.revoked).length;
  const activeCount = devices.filter((item) => !item.revoked).length;

  return (
    <>
      <PageTitle eyebrow={t("sessions.eyebrow")} title={t("sessions.title")} detail={t("sessions.detail")} />
      <p className="crumb"><Link className="pm-link" href="/settings"><Icon name="left" />{t("nav.settings")}</Link></p>
      <Notice error={error} />
      <p className="notice-success" aria-live="polite">{feedback}</p>

      <section className="panel sessions-toolbar">
        <SearchField
          className="sessions-search"
          ariaLabel={t("sessions.searchAria")}
          placeholder={t("sessions.searchPlaceholder")}
          value={query}
          onChange={setQuery}
        />
        <div className="sessions-bulk">
          <button className="btn btn-light" type="button" disabled={busy || otherActive === 0} onClick={() => void revokeOthers()}>
            <Icon name="logout" />{t("sessions.revokeAllOthers")}
          </button>
          <span className="sessions-bulk-hint">{otherActive === 0 ? t("sessions.noneActive") : t("sessions.revokeAllOthersHint")}</span>
        </div>
      </section>

      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>{t("settings.devicesTitle")}</h2>
            <p className="muted">{t("settings.sessionsPanelNote")}</p>
          </div>
          <span className="tag tag-solid">{activeCount} {t("sessions.active")}</span>
        </div>

        <div className="session-list">
          {visible.map((item) => {
            const off = Boolean(item.revoked);
            return (
              <div className={`session-row${off ? " is-off" : ""}`} key={item.id}>
                <span className={`session-state${off ? " is-off" : ""}`} aria-hidden="true"><Icon name={off ? "close" : "check"} size={13} /></span>
                <div className="session-body">
                  <strong>
                    {item.device || t("settings.unnamedDevice")}
                    {item.current && <span className="tag tag-blue">{t("sessions.currentBadge")}</span>}
                  </strong>
                  <span className="session-meta">
                    {t("sessions.lastSeen", { created: stamp(item.created, localeTag(), { dateStyle: "medium", timeStyle: "short" }) })}
                    {" · "}
                    {t("sessions.expires", { expires: stamp(item.expires, localeTag(), { dateStyle: "medium" }) })}
                  </span>
                  {item.short && <code className="session-id">{t("sessions.id")} {item.short}</code>}
                </div>
                <span className="tag tag-muted">{off ? t("sessions.signedOut") : t("sessions.active")}</span>
                {!off && !item.current && (
                  <button className="secondary" type="button" disabled={busy} onClick={() => void revoke(item.id)}>
                    <Icon name="logout" />{t("nav.logout")}
                  </button>
                )}
              </div>
            );
          })}
          {!visible.length && !loading && (
            <Empty>{needle ? t("sessions.noMatch") : t("sessions.noSessions")}</Empty>
          )}
        </div>
      </section>
    </>
  );
}
