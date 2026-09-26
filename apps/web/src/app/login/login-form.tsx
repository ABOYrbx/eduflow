"use client";

import { FormEvent, useState } from "react";

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
    if (!response?.ok) { setError(reply?.error ?? "Verbindung zum Server fehlgeschlagen."); return; }
    if (reply?.status === "2fa_required") { setPending(true); return; }
    window.location.assign("/");
  }

  return <div className="auth-card">
    <h2>{pending ? "Zwei-Faktor-Code" : "Bei EduFlow anmelden"}</h2>
    {pending && <p className="sub">EduFlow erfordert 2FA. Gib den Code aus deiner Anmeldung ein.</p>}
    <form onSubmit={submit}>
      {pending ? <>
        <label htmlFor="code">Code</label>
        <input className="input-pill" id="code" name="code" placeholder="2FA-Code" inputMode="numeric" autoComplete="one-time-code" required autoFocus />
      </> : <>
        <label htmlFor="subdomain">Schul-Subdomain</label>
        <input className="input-pill" id="subdomain" name="subdomain" placeholder="z. B. meine-schule" autoComplete="organization" defaultValue="demo" />
        <label htmlFor="username">Benutzername</label>
        <input className="input-pill" id="username" name="username" autoComplete="username" required />
        <label htmlFor="password">Passwort</label>
        <input className="input-pill" id="password" name="password" type="password" autoComplete="current-password" required />
        <label className="check" style={{ marginTop: 14 }}><input type="checkbox" name="remember" value="1" defaultChecked /> Angemeldet bleiben (30 Tage)</label>
      </>}
      {error && <p className="notice" role="alert">{error}</p>}
      <button className="btn btn-primary" type="submit" disabled={busy}>{busy ? "Einen Moment …" : pending ? "Bestätigen" : "Anmelden"}</button>
      {pending && <button className="btn btn-light btn-block" type="button" onClick={() => { setPending(false); setError(""); }}>Zurück zum Login</button>}
    </form>
  </div>;
}
