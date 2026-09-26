import { CookieJar } from "./session";

const headersOf = (cookies: string[]) => ({ get: () => null, getSetCookie: () => cookies });

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
