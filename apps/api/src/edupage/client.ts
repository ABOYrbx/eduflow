import { decodeResponse, extractCsrfToken, extractTwoFactorFields, parseUserhome } from "./protocol";
import { BadCredentialsError, CaptchaError, MissingDataError, RequestError, SecondFactorFailedError } from "./errors";
import { EdupageSession, FetchImpl } from "./session";

export interface LoginOk {
  outcome: "ok";
  data: unknown;
  gsecHash: string | null;
  subdomain: string;
  username: string;
}

export interface TwoFactorFields { gu: string; au: string; csrf: string; }

export interface LoginTwoFactor {
  outcome: "twofactor";
  /** Echte Subdomain (nach login1-Auflösung), Host für Cookie-Ablage. */
  subdomain: string;
  fields: TwoFactorFields;
  /** Alle Cookies des begonnenen Logins (für Request-übergreifende 2FA). */
  cookies: Record<string, string>;
  finishWithCode(code: string): Promise<LoginOk>;
}

export type LoginResult = LoginOk | LoginTwoFactor;

/** EduPage-Client (Port von `edupage_api.login`, Paket N-A).
 *
 * Ablauf wie Python: RPC (`getToken` → `login` → Redirect) zuerst,
 * Formular-Fallback danach; 2FA per `finish_with_code` (E-Mail-/App-Code).
 * Netzwerk kommt ausschließlich über injiziertes Fetch (offline Specs).
 */
export class EdupageClient {
  readonly session: EdupageSession;

  constructor(fetchImpl?: FetchImpl) {
    this.session = new EdupageSession(fetchImpl);
  }

  /** Cookie-Host zur Subdomain (`demo` → `demo.edupage.org`). */
  static hostFor(subdomain: string): string {
    return subdomain.includes(".") ? subdomain.toLowerCase() : `${subdomain.toLowerCase()}.edupage.org`;
  }

  /** Alle Cookies des Logins (für Request-übergreifende 2FA). */
  cookiesFor(subdomain: string): Record<string, string> {
    return this.session.jar.all(EdupageClient.hostFor(subdomain));
  }

  /** Cookies eines begonnenen Logins laden (Fortsetzung im neuen Request). */
  loadCookies(subdomain: string, cookies: Record<string, string>): void {
    this.session.jar.load(EdupageClient.hostFor(subdomain), cookies);
  }

  private parseRpc(text: string): Record<string, unknown> | null {
    if (!text) return null;
    try {
      return JSON.parse(decodeResponse(text)) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  private async loginRpc(username: string, password: string, subdomain: string): Promise<LoginResult | null> {
    const base = `https://${subdomain}.edupage.org`;
    const landing = await this.session.get(`${base}/login/?cmd=MainLogin`);
    if (landing.status !== 200) return null;

    const tokenPage = await this.session.postRpc(
      `${base}/login/?cmd=MainLogin&akcia=getToken`,
      JSON.stringify({ username, edupage: "" }),
    );
    if (tokenPage.status !== 200) return null;
    const tokenBody = this.parseRpc(tokenPage.text);
    const token = typeof tokenBody?.token === "string" ? tokenBody.token : null;
    if (!token) return null;

    const loginBody = JSON.stringify({ username, password, userToken: token, edupage: "", ctxt: "", tu: null, gu: null, au: null });
    const loginPage = await this.session.postRpc(`${base}/login/?cmd=MainLogin&akcia=login`, loginBody);
    if (loginPage.status !== 200) return null;
    const loginResult = this.parseRpc(loginPage.text);
    if (!loginResult) return null;
    const errorId = (loginResult.err as Record<string, unknown> | undefined)?.error_id;
    const redirectUrl = typeof loginResult.redirectUrl === "string" ? loginResult.redirectUrl : null;
    if (errorId === "invalid_token" || !redirectUrl) return null;

    const target = new URL(redirectUrl, base).toString();
    return this.finishLogin(await this.session.get(target), subdomain, username);
  }

  private async loginForm(username: string, password: string, subdomain: string): Promise<LoginResult> {
    const base = `https://${subdomain}.edupage.org`;
    const landing = await this.session.get(`${base}/login/?cmd=MainLogin`);
    const csrf = extractCsrfToken(landing.text);
    if (!csrf) throw new BadCredentialsError("EduPage did not provide a login token");
    const done = await this.session.postForm(`${base}/login/edubarLogin.php`, { csrfauth: csrf, username, password });
    if (done.url.includes("cap=1") || done.url.includes("lerr=b43b43")) throw new CaptchaError("captcha");
    if (done.url.includes("bad=1")) throw new BadCredentialsError("bad credentials");
    return this.finishLogin(done, subdomain, username);
  }

  private async finishLogin(page: { status: number; url: string; text: string }, subdomain: string, username: string): Promise<LoginResult> {
    let realSubdomain = subdomain;
    if (subdomain === "login1") {
      const host = new URL(page.url).hostname.split(".")[0] ?? subdomain;
      realSubdomain = host;
    }
    if (!page.url.includes("twofactor")) {
      try {
        const parsed = parseUserhome(page.text);
        return { outcome: "ok", data: parsed.data, gsecHash: parsed.gsecHash, subdomain: realSubdomain, username };
      } catch {
        throw new BadCredentialsError("EduPage did not return login data");
      }
    }
    const twofaPage = await this.session.get(`https://${realSubdomain}.edupage.org/login/twofactor?sn=1`);
    const fields = extractTwoFactorFields(twofaPage.text);
    if (!fields) throw new BadCredentialsError("EduPage did not provide two-factor fields");
    const finishWithCode = async (code: string): Promise<LoginOk> =>
      this.finishTwoFactor(realSubdomain, fields, code, username);
    return {
      outcome: "twofactor",
      subdomain: realSubdomain,
      fields,
      cookies: this.cookiesFor(realSubdomain),
      finishWithCode,
    };
  }

  /** Begonnenen 2FA-Ablauf abschließen (eigene Session, z. B. neuer Request). */
  async finishTwoFactor(subdomain: string, fields: TwoFactorFields, code: string, username = ""): Promise<LoginOk> {
    const host = EdupageClient.hostFor(subdomain);
    const done = await this.session.postForm(`https://${host}/login/edubarLogin.php`, {
      csrfauth: fields.csrf,
      t2fasec: code,
      "2fNoSave": "y",
      "2fform": "1",
      gu: fields.gu,
      au: fields.au,
    });
    if (!done.text.includes("window.location = gu;")) {
      throw new SecondFactorFailedError("Second factor failed (wrong/expired code?)");
    }
    const sessionId = this.session.jar.get(host, "PHPSESSID");
    if (!sessionId) throw new MissingDataError("missing PHPSESSID after 2fa");
    return this.reloadData(subdomain, sessionId, username);
  }

  async login(username: string, password: string, subdomain = "login1"): Promise<LoginResult> {
    try {
      const viaRpc = await this.loginRpc(username, password, subdomain);
      if (viaRpc) return viaRpc;
    } catch (error) {
      if (error instanceof CaptchaError || error instanceof BadCredentialsError) throw error;
      throw new RequestError(`login transport failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    return this.loginForm(username, password, subdomain);
  }

  async reloadData(subdomain: string, sessionId: string, username: string): Promise<LoginOk> {
    const host = EdupageClient.hostFor(subdomain);
    this.session.jar.set(host, "PHPSESSID", sessionId);
    const page = await this.session.get(`https://${host}/user`);
    try {
      const parsed = parseUserhome(page.text);
      return { outcome: "ok", data: parsed.data, gsecHash: parsed.gsecHash, subdomain, username };
    } catch {
      throw new BadCredentialsError(`Invalid session id for ${subdomain}`);
    }
  }
}
