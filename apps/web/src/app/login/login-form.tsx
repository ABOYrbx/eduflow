"use client";

import { FormEvent, useState } from "react";
import { t } from "../../lib/i18n";

type LoginReply = { status?: string; error?: string; code?: string; message?: string };

export function LoginForm() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError("");
    const form = new FormData(event.currentTarget);
    const response = await fetch(pending ? "/api/auth/2fa" : "/api/auth/login", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify(pending ? { code: String(form.get("code") ?? "") } : {
        subdomain: String(form.get("subdomain") ?? ""), username: String(form.get("username") ?? ""),
        password: String(form.get("password") ?? ""), device: "EduFlow Web", remember: form.has("remember"),
      }),
    }).catch(() => null);
    const reply = await response?.json().catch(() => ({})) as LoginReply | undefined;
    setBusy(false);
    if (!response?.ok) { setError(reply?.error ?? t("login.connectionFailed")); return; }
    if (reply?.status === "2fa_required") { setPending(true); return; }
    window.location.assign("/");
  }

  return <div className="auth-card">
    <h2>{pending ? t("login.twoFaTitle") : t("login.title")}</h2>
    {pending && <p className="sub">{t("login.twoFaSub")}</p>}
    <form onSubmit={submit}>
      {pending ? <>
        <label htmlFor="code">{t("login.codeLabel")}</label>
        <input className="input-pill" id="code" name="code" placeholder={t("login.codePlaceholder")} inputMode="numeric" autoComplete="one-time-code" required autoFocus />
      </> : <>
        <label htmlFor="subdomain">{t("login.subdomainLabel")}</label>
        <input className="input-pill" id="subdomain" name="subdomain" placeholder={t("login.subdomainPlaceholder")} autoComplete="organization" defaultValue="demo" />
        <label htmlFor="username">{t("login.usernameLabel")}</label>
        <input className="input-pill" id="username" name="username" autoComplete="username" required />
        <label htmlFor="password">{t("login.passwordLabel")}</label>
        <input className="input-pill" id="password" name="password" type="password" autoComplete="current-password" required />
        <label className="check" style={{ marginTop: 14 }}><input type="checkbox" name="remember" value="1" defaultChecked /> {t("login.remember")}</label>
      </>}
      {error && <p className="notice" role="alert">{error}</p>}
      <button className="btn btn-primary" type="submit" disabled={busy}>{busy ? t("login.busy") : pending ? t("login.submit2fa") : t("login.submitLogin")}</button>
      {pending && <button className="btn btn-light btn-block" type="button" onClick={() => { setPending(false); setError(""); }}>{t("login.backToLogin")}</button>}
    </form>
  </div>;
}
