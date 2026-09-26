/** Minimaler Cookie-Jar + fetch-Hülle für EduPage (Paket N-A).
 *
 * Keine Extra-Dependency: `PHPSESSID`-Cookies merken und mitsenden.
 * Der Fetch-Client ist injizierbar, damit Specs offline mit Fixtures laufen.
 */
import { encodeFormData, encodeRequestBody } from "./protocol";
export interface PageResponse { status: number; url: string; text: string; }

export type FetchImpl = (url: string, init: { method: string; headers: Record<string, string>; body?: string }) => Promise<{
  status: number;
  url: string;
  headers: { get(name: string): string | null; getSetCookie?: () => string[] };
  text: () => Promise<string>;
  arrayBuffer: () => Promise<ArrayBuffer>;
}>;

const defaultFetch: FetchImpl = (url, init) => {
  const requestInit: { method: string; headers: Record<string, string>; redirect: "follow"; body?: string } =
    { method: init.method, headers: init.headers, redirect: "follow" };
  if (init.body !== undefined) requestInit.body = init.body;
  return fetch(url, requestInit).then(async (response) => ({
    status: response.status,
    url: response.url,
    headers: response.headers,
    text: () => response.text(),
    arrayBuffer: async () => response.arrayBuffer(),
  }));
};

export class CookieJar {
  private readonly store = new Map<string, Map<string, string>>();

  private domainOf(url: string): string {
    return new URL(url).hostname.toLowerCase();
  }

  setFromHeaders(url: string, headers: { get(name: string): string | null; getSetCookie?: () => string[] }): void {
    const host = this.domainOf(url);
    const raw: string[] = typeof headers.getSetCookie === "function"
      ? headers.getSetCookie()
      : (headers.get("set-cookie") ?? "").split(/,(?=[^;,]+=[^;,]*)/);
    for (const line of raw) {
      const [pair = "", ...attrs] = line.split(";");
      const eq = pair.indexOf("=");
      if (eq <= 0) continue;
      const name = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      if (!name) continue;
      let domain = host;
      let drop = false;
      for (const attr of attrs) {
        const [key = "", ...rest] = attr.trim().split("=");
        const lower = key.toLowerCase();
        const restValue = rest.join("=").trim();
        if (lower === "domain" && restValue) domain = restValue.replace(/^\./, "").toLowerCase();
        if (lower === "expires" && restValue && Date.parse(restValue) <= Date.now()) drop = true;
        if (lower === "max-age" && Number.parseInt(restValue, 10) <= 0) drop = true;
      }
      if (!this.store.has(domain)) this.store.set(domain, new Map());
      if (drop) this.store.get(domain)?.delete(name);
      else this.store.get(domain)?.set(name, value);
    }
  }

  headerFor(url: string): string {
    const host = this.domainOf(url);
    const parts: string[] = [];
    for (const [domain, cookies] of this.store) {
      if (host === domain || host.endsWith(`.${domain}`)) {
        for (const [name, value] of cookies) parts.push(`${name}=${value}`);
      }
    }
    return parts.join("; ");
  }

  get(host: string, name: string): string | undefined {
    const lower = host.toLowerCase();
    for (const [domain, cookies] of this.store) {
      if (lower === domain || lower.endsWith(`.${domain}`)) {
        const value = cookies.get(name);
        if (value !== undefined) return value;
      }
    }
    return undefined;
  }

  set(host: string, name: string, value: string): void {
    const lower = host.toLowerCase();
    if (!this.store.has(lower)) this.store.set(lower, new Map());
    this.store.get(lower)?.set(name, value);
  }

  all(host: string): Record<string, string> {
    const lower = host.toLowerCase();
    const out: Record<string, string> = {};
    for (const [domain, cookies] of this.store) {
      if (lower === domain || lower.endsWith(`.${domain}`)) {
        for (const [name, value] of cookies) out[name] = value;
      }
    }
    return out;
  }

  load(host: string, cookies: Record<string, string>): void {
    for (const [name, value] of Object.entries(cookies)) this.set(host, name, value);
  }
}

export class EdupageSession {
  readonly jar = new CookieJar();

  constructor(private readonly fetchImpl: FetchImpl = defaultFetch) {}

  private async request(url: string, method: string, headers: Record<string, string>, body?: string): Promise<PageResponse> {
    const cookie = this.jar.headerFor(url);
    const outgoing: Record<string, string> = { ...(cookie ? { Cookie: cookie } : {}), ...headers };
    const init: { method: string; headers: Record<string, string>; body?: string } = { method, headers: outgoing };
    if (body !== undefined) init.body = body;
    const response = await this.fetchImpl(url, init);
    this.jar.setFromHeaders(url, response.headers);
    return { status: response.status, url: response.url, text: await response.text() };
  }

  get(url: string): Promise<PageResponse> {
    return this.request(url, "GET", {});
  }

  postForm(url: string, params: Record<string, string>): Promise<PageResponse> {
    return this.request(url, "POST", { "Content-Type": "application/x-www-form-urlencoded" }, encodeFormData(params));
  }

  /** Roher Body (z. B. `dz:`-RPC) ohne weitere Kodierung senden. */
  postRaw(url: string, body: string, headers: Record<string, string> = {}): Promise<PageResponse> {
    return this.request(url, "POST", { "Content-Type": "application/x-www-form-urlencoded", ...headers }, body);
  }

  /** `eqap`-Body wie die JS-Referenzlib (`eqap=<b64(urlencode)>&eqaz=0`). */
  postEqap(url: string, params: Record<string, string>, headers: Record<string, string> = {}): Promise<PageResponse> {
    const query = Object.entries(params)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join("&");
    const body = `eqap=${encodeURIComponent(Buffer.from(query, "utf8").toString("base64"))}&eqaz=0`;
    return this.request(url, "POST", { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", ...headers }, body);
  }

  async getBytes(url: string): Promise<{ status: number; url: string; contentType: string; bytes: Buffer }> {
    const cookie = this.jar.headerFor(url);
    const response = await this.fetchImpl(url, { method: "GET", headers: cookie ? { Cookie: cookie } : {} });
    this.jar.setFromHeaders(url, response.headers);
    return { status: response.status, url: response.url, contentType: response.headers.get("content-type") ?? "", bytes: Buffer.from(await response.arrayBuffer()) };
  }

  postRpc(url: string, rpcparams: string): Promise<PageResponse> {
    const body = encodeRequestBody({ rpcparams });
    return this.request(url, "POST", { "Content-Type": "application/x-www-form-urlencoded" }, body);
  }
}
