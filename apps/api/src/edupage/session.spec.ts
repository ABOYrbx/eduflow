import { CookieJar, EdupageSession, FetchImpl } from "./session";

const headersOf = (cookies: string[], location: string | null = null) => ({
  get: (name: string) => (name.toLowerCase() === "location" ? location : null),
  getSetCookie: () => cookies,
});

describe("CookieJar", () => {
  it("merkt PHPSESSID und sendet sie an Subdomains", () => {
    const jar = new CookieJar();
    jar.setFromHeaders("https://demo.edupage.org/login/", headersOf(["PHPSESSID=sess-1; path=/; HttpOnly"]));
    expect(jar.headerFor("https://demo.edupage.org/user")).toBe("PHPSESSID=sess-1");
    expect(jar.headerFor("https://anderes.example.org/")).toBe("");
    expect(jar.get("demo.edupage.org", "PHPSESSID")).toBe("sess-1");
  });

  it("wirft abgelaufene Cookies weg", () => {
    const jar = new CookieJar();
    jar.setFromHeaders("https://demo.edupage.org/", headersOf(["PHPSESSID=alt; expires=Thu, 01 Jan 1970 00:00:00 GMT"]));
    expect(jar.headerFor("https://demo.edupage.org/")).toBe("");
  });
});

describe("EdupageSession Redirects", () => {
  it("reicht Cookies jedes Hops weiter (wie requests)", async () => {
    const seen: string[] = [];
    const fetch: FetchImpl = async (url, init) => {
      seen.push(`${init.method} ${url} :: ${init.headers.Cookie ?? "-"} :: ${init.redirect}`);
      if (url.endsWith("/start")) {
        return { status: 302, url, headers: headersOf(["hop=1; Path=/"], "/mid"), text: async () => "", arrayBuffer: async () => new ArrayBuffer(0) };
      }
      if (url.endsWith("/mid")) {
        return { status: 302, url, headers: headersOf(["hop2=2; Path=/"], "/end"), text: async () => "", arrayBuffer: async () => new ArrayBuffer(0) };
      }
      return { status: 200, url, headers: headersOf([]), text: async () => "fertig", arrayBuffer: async () => new ArrayBuffer(0) };
    };
    const session = new EdupageSession(fetch);
    const page = await session.get("https://demo.edupage.org/start");
    expect(page).toMatchObject({ status: 200, url: "https://demo.edupage.org/end", text: "fertig" });
    expect(seen).toEqual([
      "GET https://demo.edupage.org/start :: - :: manual",
      "GET https://demo.edupage.org/mid :: hop=1 :: manual",
      "GET https://demo.edupage.org/end :: hop=1; hop2=2 :: manual",
    ]);
    expect(session.jar.get("demo.edupage.org", "hop2")).toBe("2");
  });
});
