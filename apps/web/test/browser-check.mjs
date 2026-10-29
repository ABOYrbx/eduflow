/**
 * Browser-Abnahme der Web-UI gegen die laufende Demo-API.
 *
 * Prueft im echten Browser (Chrome via Playwright), was die Jest-Tests
 * nicht koennen: Hydration, Persistenz ueber eine Neuladung und das
 * Ausbleiben von Netzfehlern.
 *
 * Start vorher die Dienste:
 *   API (Fake-Provider, Port 3100) und Web (Port 8200) wie in run.sh,
 *   dann:  node apps/web/test/browser-check.mjs
 *
 * Playwright wird nicht mitinstalliert, sondern ad hoc geholt:
 *   npm install --no-save playwright   (benoetigt ein installiertes Chrome)
 *
 * Nicht Teil von `npm test` — haengt an einem Browser und an laufenden
 * Diensten.
 */
import { chromium } from "playwright";
const BASE = "http://127.0.0.1:8200";
const out = [];
const log = (ok, what, extra = "") => out.push(`${ok ? "OK  " : "FAIL"}  ${what}${extra ? " — " + extra : ""}`);
const b = await chromium.launch({ channel: "chrome" });
const ctx = await b.newContext({ locale: "en-GB", extraHTTPHeaders: { "accept-language": "en-GB,en;q=0.9" } });
const p = await ctx.newPage();
const net = [], pageErrors = [];
p.on("pageerror", (e) => pageErrors.push(String(e).slice(0, 100)));
p.on("response", (r) => { if (r.status() >= 400) net.push(`${r.status()} ${new URL(r.url()).pathname}`); });

await p.goto(BASE + "/", { waitUntil: "networkidle" });
log(p.url().endsWith("/login"), "Ohne Sitzung: / fuehrt zu /login");
log(await p.locator(".lang-wrap.auth-top-left .lang-btn").isVisible(), "Sprachpicker oben links (geteiltes Bauteil)");
log(await p.locator("button.theme-toggle.auth-top-right").isVisible(), "Theme-Schalter oben rechts (geteiltes Bauteil)");
await p.fill("#subdomain", "demo"); await p.fill("#username", "demo"); await p.fill("#password", "demo");
await p.click("button.btn-primary");
await p.waitForURL(BASE + "/", { timeout: 20000 });
log(true, "Login laeuft ueber JS — Hydration greift");
await p.waitForSelector(".ov-grid", { timeout: 20000 });
log((await p.locator(".nav-pill").count()) >= 6, "Navigation gerendert", `${await p.locator(".nav-pill").count()} Eintraege`);
log((await p.locator(".clock-time").innerText()).trim().length > 0, "Uhr laeuft", (await p.locator(".clock-time").innerText()).trim());
log(await p.locator(".now-card").isVisible(), "Jetzt-Karte gerendert");
await p.click('button[aria-pressed]'); await p.waitForSelector(".sec-bar");
const before = (await p.locator(".sec-bar-name").first().innerText()).trim();
await p.click('.sec-bar button[aria-label*="down"]'); await p.waitForTimeout(1300);
const after = (await p.locator(".sec-bar-name").first().innerText()).trim();
log(before !== after, "Editor: Umsortieren wirkt sofort", `${before} -> ${after}`);
await p.reload({ waitUntil: "networkidle" }); await p.waitForSelector(".ov-grid");
const reloaded = (await p.locator(".ov-slot h2").first().innerText()).trim();
log(reloaded.toLowerCase().startsWith(after.toLowerCase()), "Editor: Reihenfolge ueberlebt die Neuladung", `${after} -> ${reloaded}`);
await p.click('button[aria-pressed]'); await p.waitForSelector(".sec-bar");
const labels = await p.locator(".sec-bar button").evaluateAll((e) => e.map((x) => x.getAttribute("aria-label") || ""));
log(labels.length > 0 && !labels.some((l) => /\{[a-z]+\}/i.test(l)), "aria-labels ohne unaufgeloeste Platzhalter", `${labels.length} Labels`);
log((await ctx.cookies()).some((c) => c.name === "eduflow_access"), "httpOnly-Sitzungs-Cookie gesetzt");
log(pageErrors.length === 0, "Keine JavaScript-Ausnahmen", pageErrors.slice(0, 2).join(" | ") || "keine");
log(net.length === 0, "Keine 4xx/5xx-Antworten", net.slice(0, 3).join(" | ") || "keine");
await b.close();
console.log(out.join("\n"));
process.exit(out.some((l) => l.startsWith("FAIL")) ? 1 : 0);
