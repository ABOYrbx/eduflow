import { EdupageClient } from "./client";
import { BadCredentialsError, CaptchaError, SecondFactorFailedError } from "./errors";
import type { FetchImpl } from "./session";

interface Route { status: number; url: string; text: string; setCookie?: string[]; location?: string; }

const USERHOME = '<html><script>userhome({"subdomain":"demo","id":7});</script><script>ASC.gsechash="gsec-1";</script></html>';
const TWOFA = '<input name="csrfauth" value="csrf-1"><input name="au" value="au-2"><input name="gu" value="gu-3">';

function stubFetch(routes: Record<string, Route>, seen: string[] = []): FetchImpl {
  return async (url, init) => {
    const key = `${init.method} ${url}`;
    seen.push(`${key} :: ${(init.body ?? "").slice(0, 60)}`);
    const route = routes[key];
    if (!route) throw new Error(`unerwarteter Request: ${key}`);
    return {
      status: route.status,
      url: route.url,
      headers: {
        get: (name: string) => (name.toLowerCase() === "location" ? (route.location ?? null) : null),
        getSetCookie: () => route.setCookie ?? [],
      },
      text: async () => route.text,
      arrayBuffer: async () => new ArrayBuffer(0),
    };
  };
}

const rpcOk: Record<string, Route> = {
  "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/user","err":{}}' },
  "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: USERHOME },
};

describe("EdupageClient (Port von edupage_api.login)", () => {
  it("meldet sich per RPC an und parst userhome", async () => {
    const seen: string[] = [];
    const result = await new EdupageClient(stubFetch(rpcOk, seen)).login("demo", "geheim", "demo");
    expect(result.outcome).toBe("ok");
    if (result.outcome !== "ok") throw new Error("kein ok");
    expect(result.subdomain).toBe("demo");
    expect(result.data).toEqual({ subdomain: "demo", id: 7 });
    expect(result.gsecHash).toBe("gsec-1");
    expect(seen.some((line) => line.includes("eqap=dz"))).toBe(true);
  });

  it("führt 2FA per E-Mail-Code zu Ende", async () => {
    const routes: Record<string, Route> = {
      ...rpcOk,
      "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/login/twofactor?sn=0","err":{}}' },
      "GET https://demo.edupage.org/login/twofactor?sn=0": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=0", text: "<html>weiter</html>" },
      "GET https://demo.edupage.org/login/twofactor?sn=1": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=1", text: TWOFA },
      "POST https://demo.edupage.org/login/edubarLogin.php": { status: 200, url: "https://demo.edupage.org/login/edubarLogin.php", text: "<script>window.location = gu;</script>", setCookie: ["PHPSESSID=sess-9; path=/"] },
    };
    const result = await new EdupageClient(stubFetch(routes)).login("demo", "geheim", "demo");
    expect(result.outcome).toBe("twofactor");
    if (result.outcome !== "twofactor") throw new Error("kein twofactor");
    const done = await result.finishWithCode("123456");
    expect(done.outcome).toBe("ok");
    expect(done.username).toBe("demo");
  });

  it("meldet falschen 2FA-Code wie Python", async () => {
    const routes: Record<string, Route> = {
      ...rpcOk,
      "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: '{"redirectUrl":"/login/twofactor?sn=0","err":{}}' },
      "GET https://demo.edupage.org/login/twofactor?sn=0": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=0", text: "<html>weiter</html>" },
      "GET https://demo.edupage.org/login/twofactor?sn=1": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=1", text: TWOFA },
      "POST https://demo.edupage.org/login/edubarLogin.php": { status: 200, url: "https://demo.edupage.org/login/edubarLogin.php", text: "<html>Fehler</html>" },
    };
    const result = await new EdupageClient(stubFetch(routes)).login("demo", "geheim", "demo");
    if (result.outcome !== "twofactor") throw new Error("kein twofactor");
    await expect(result.finishWithCode("000000")).rejects.toBeInstanceOf(SecondFactorFailedError);
  });

  it("wirft BadCredentials ohne CSRF-Token im Fallback", async () => {
    const routes: Record<string, Route> = {
      "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>ohne Token</html>" },
      "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 500, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: "" },
    };
    await expect(new EdupageClient(stubFetch(routes)).login("demo", "falsch", "demo")).rejects.toBeInstanceOf(BadCredentialsError);
  });

  it("erkennt Captcha im Fallback wie Python", async () => {
    const routes: Record<string, Route> = {
      "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: '{"csrftoken":"csrf-0"}' },
      "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 500, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: "" },
      "POST https://demo.edupage.org/login/edubarLogin.php": { status: 302, url: "https://demo.edupage.org/login/edubarLogin.php", text: "", location: "https://demo.edupage.org/login/edubarLogin.php?cap=1" },
      "GET https://demo.edupage.org/login/edubarLogin.php?cap=1": { status: 200, url: "https://demo.edupage.org/login/edubarLogin.php?cap=1", text: "" },
    };
    await expect(new EdupageClient(stubFetch(routes)).login("demo", "geheim", "demo")).rejects.toBeInstanceOf(CaptchaError);
  });
});
