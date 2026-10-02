"use client";

import Link from "next/link";
import { FormEvent, Fragment, useCallback, useEffect, useState } from "react";
import { t } from "../../lib/i18n";
import { useLocale } from "../../lib/locale-context";
import { normalizeHidden, normalizeOrder, normalizeSpans, SECTION_KEYS, serializeSpans, type SectionState } from "../../lib/section-layout";
import { api } from "../../lib/api";
import { formatDate } from "../../lib/format";
import type { Device, Settings } from "../../lib/types";
import { Icon } from "../icon";
import { LanguagePicker } from "../language-picker";
import { NumberField } from "../number-field";
import { Select } from "../select-field";
import { SectionEditor } from "../section-editor";
import { Notice, PageTitle } from "../ui";

declare global {
  interface Window {
    /** Öffentliche API von `public/theme.js` (Theme + Akzentfarben). */
    EduFlowTheme?: {
      choice(): string;
      setChoice(value: string): void;
      accent(): string;
      setAccent(value: string): void;
    };
  }
}

export function SettingsView() {
  useLocale(); // abonniert den Sprachwechsel, damit alle t()-Texte neu rendern
  const [settings, setSettings] = useState<Settings | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [error, setError] = useState(""); const [feedback, setFeedback] = useState(""); const [busy, setBusy] = useState(false);
  const [deviceName, setDeviceName] = useState(""); const [newToken, setNewToken] = useState<{ token: string; refresh_token?: string; expires: string; device: string } | null>(null);
  const [themeChoice, setThemeChoice] = useState("system"); const [accent, setAccent] = useState("black");
  const [order, setOrder] = useState("messages,homework,weather");
  const [layout, setLayout] = useState<SectionState>({ order: SECTION_KEYS.slice(), hidden: [], spans: {} });
  const layoutOrder = normalizeOrder({ ov_order: layout.order.join(",") });
  const layoutHidden = layout.hidden;
  const sectionHints = { drag: t("overview.editorDrag"), up: t("settings.moveUp"), down: t("settings.moveDown"), hide: t("overview.editorHide"), show: t("overview.editorShow"), hidden: t("overview.editorHidden"), wide: t("overview.editorWide"), narrow: t("overview.editorNarrow") };
  const [cityValue, setCityValue] = useState(""); const [cityQuery, setCityQuery] = useState("");
  const [cityOptions, setCityOptions] = useState<Array<{ name: string; country?: string }>>([]); const [cityStatus, setCityStatus] = useState("");
  const load = useCallback(async () => {
    try {
      const [nextSettings, nextDevices] = await Promise.all([api<Settings>("/settings"), api<{ items: typeof devices }>("/devices")]);
      setSettings(nextSettings); setDevices(nextDevices.items); setError("");
      setOrder(String(nextSettings.values.ov_order ?? "messages,homework,weather"));
      setLayout({ order: normalizeOrder(nextSettings.values), hidden: normalizeHidden(nextSettings.values), spans: normalizeSpans(nextSettings.values) });
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
      setSettings({ ...settings, values: result.values }); setOrder(String(result.values.ov_order ?? order)); setLayout({ order: normalizeOrder(result.values), hidden: normalizeHidden(result.values), spans: normalizeSpans(result.values) }); setCityValue(String(result.values.wetter_city ?? "")); setFeedback(t("settings.saved")); setError("");
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
    {settings && <form className="panel settings-form" onSubmit={save} aria-labelledby="set-general"><h2 className="set-title" id="set-general">{t("settings.generalTitle")}</h2><p className="set-note">{t("settings.generalNote")}</p><input type="hidden" name="ov_order" value={layoutOrder.join(",")} /><input type="hidden" name="ov_hidden" value={layoutHidden.join(",")} /><input type="hidden" name="ov_span" value={serializeSpans(layout.spans, layout.order)} />{settings.schema.map((item, index) => <Fragment key={item.key}>{item.section && settings.schema[index - 1]?.section !== item.section && <h3 className="set-sub">{item.section}</h3>}{item.kind === "bool" ? item.key === "ov_wetter" ? <label className="setting-switch" htmlFor={`set-${item.key}`}><span className="setting-switch-copy"><span className="setting-switch-title">{item.label}</span><span className="setting-switch-hint">{item.hint ?? ""}</span></span><input className="setting-switch-input" id={`set-${item.key}`} type="checkbox" name={item.key} defaultChecked={settings.values[item.key] === true} /><span className="setting-switch-track" aria-hidden="true"><span /></span></label> : <label className="check"><input type="checkbox" name={item.key} defaultChecked={settings.values[item.key] === true} /> {item.label}</label> : item.kind === "select" ? <div className="field"><label id={`set-${item.key}-label`}>{item.label}</label><Select labelledBy={`set-${item.key}-label`} name={item.key} testId={`set-${item.key}`} defaultValue={String(settings.values[item.key] ?? item.default)} options={(item.options ?? []).map(([value, label]) => ({ value, label }))} /></div> : item.kind === "int" ? <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><NumberField id={`set-${item.key}`} name={item.key} min={item.min} max={item.max} value={Number(settings.values[item.key] ?? item.default)} onChange={(next) => setSettings({ ...settings, values: { ...settings.values, [item.key]: next } })} />{item.hint && <div className="field-hint">{item.hint}</div>}</div> : item.kind === "order" ? <div className="field"><label>{item.label}</label><SectionEditor layout={layout} labels={orderLabels} hints={sectionHints} onChange={setLayout} /><div className="field-hint">{t("settings.orderHint")}</div></div>: item.kind === "hidden" ? <div className="field"><label>{item.label}</label>{item.hint && <div className="field-hint">{item.hint}</div>}</div> : item.key === "wetter_city" ? <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><div className="weather-city-search"><input className="input-pill" id={`set-${item.key}`} type="text" name={item.key} value={cityValue} maxLength={item.maxlength ?? 100} placeholder={item.placeholder ?? t("settings.cityPlaceholder")} autoComplete="off" role="combobox" aria-autocomplete="list" aria-expanded={Boolean(cityQuery && (cityOptions.length || cityStatus))} aria-controls="weather-city-options" onChange={(event) => { setCityValue(event.target.value); setCityQuery(event.target.value); }} onKeyDown={(event) => { if (event.key === "Escape") { setCityQuery(""); setCityOptions([]); } if (event.key === "Enter" && cityOptions.length) { event.preventDefault(); setCityValue(cityOptions[0].name); setCityQuery(""); setCityOptions([]); } }} /><div className="weather-city-options" id="weather-city-options" role="listbox" hidden={!cityQuery || (!cityOptions.length && !cityStatus)}>{cityStatus && <div className="weather-city-status" role="status">{cityStatus}</div>}{cityOptions.map((option) => <button className="weather-city-option" type="button" role="option" key={`${option.name}-${option.country}`} onClick={() => { setCityValue(option.name); setCityQuery(""); setCityOptions([]); }}><span className="weather-city-option-title">{option.name}</span>{option.country && <span className="weather-city-option-detail">{option.country}</span>}</button>)}</div></div>{item.hint && <div className="field-hint">{item.hint}</div>}</div> : <div className="field"><label htmlFor={`set-${item.key}`}>{item.label}</label><input className="input-pill" id={`set-${item.key}`} name={item.key} maxLength={item.maxlength} defaultValue={String(settings.values[item.key] ?? item.default ?? "")} placeholder={item.placeholder} />{item.hint && <div className="field-hint">{item.hint}</div>}</div>}</Fragment>)}<div><button className="btn btn-primary" disabled={busy}><Icon name="save" />{busy ? t("settings.saving") : t("settings.save")}</button></div></form>}
    <section className="panel"><div className="panel-heading"><div><p className="eyebrow">{t("settings.sessionsEyebrow")}</p><h2>{t("settings.devicesTitle")}</h2><p className="muted">{t("settings.sessionsPanelNote")}</p></div><span className="tag tag-solid">{devices.filter((device) => !device.revoked).length} {t("sessions.active")}</span></div><div className="device-row"><div><strong>{t("sessions.currentBadge")}</strong><span>{t("settings.loggedInAt", { created: formatDate(devices.find((device) => device.current)?.created ?? ""), expires: formatDate(devices.find((device) => device.current)?.expires ?? "") })}</span></div><Link className="btn btn-primary btn-sm" href="/sessions"><Icon name="device" />{t("sessions.openSettings")}</Link></div></section>
    <section className="panel" aria-labelledby="set-api"><h2 className="set-title" id="set-api">{t("settings.apiTitle")}</h2><p className="set-note">{t("settings.apiNote")}</p>
      <form className="device-token-form" onSubmit={(event) => void createDeviceToken(event)}><div className="field"><label htmlFor="api-device">{t("settings.deviceNameLabel")}</label><input className="input-pill" id="api-device" value={deviceName} onChange={(event) => setDeviceName(event.target.value)} placeholder={t("settings.deviceNamePlaceholder")} maxLength={80} autoComplete="off" /></div><button className="btn btn-primary" type="submit" disabled={busy}><Icon name="key" />{busy ? t("settings.creating") : t("settings.createToken")}</button></form>
      {newToken && <div className="new-token-result" role="status"><p className="notice"><strong>{t("settings.newTokenFor", { device: newToken.device })}</strong></p><div className="token-box"><span>{t("settings.accessLabel")}</span><code>{newToken.token}</code><button className="btn btn-light btn-sm" type="button" onClick={() => void copyToken(newToken.token, t("settings.accessTokenLabel"))}><Icon name="copy" />{t("settings.copy")}</button></div>{newToken.refresh_token && <div className="token-box"><span>{t("settings.refreshLabel")}</span><code>{newToken.refresh_token}</code><button className="btn btn-light btn-sm" type="button" onClick={() => void copyToken(newToken.refresh_token ?? "", t("settings.refreshTokenLabel"))}><Icon name="copy" />{t("settings.copy")}</button></div>}<p className="set-note">{t("settings.validUntil", { date: formatDate(newToken.expires) })} {newToken.refresh_token ? t("settings.storeBoth") : t("settings.storeOne")} {t("settings.storeHint")}</p></div>}
    </section>
    <section className="panel"><h2 className="set-title">{t("settings.dataTitle")}</h2><p className="set-note">{t("settings.dataNote")}</p><button className="btn btn-light" type="button" onClick={() => void clearCache()}><Icon name="trash" />{t("settings.clearCache")}</button></section>
  </>;
}
