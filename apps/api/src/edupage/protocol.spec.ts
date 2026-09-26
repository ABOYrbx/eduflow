import { decodeResponse, encodeFormData, encodeRequestBody, extractCsrfToken, extractTwoFactorFields, parseUserhome, quote } from "./protocol";

describe("protocol (Parität zu edupage_api.compression/login)", () => {
  it("kodiert Formulardaten wie urllib.parse.quote", () => {
    expect(encodeFormData({ a: "b c", d: "e/f", e: "a+b" })).toBe("a=b%20c&d=e/f&e=a%2Bb");
    expect(quote("a/b?c=d&e")).toBe("a/b%3Fc%3Dd%26e");
  });

  it("baut den RPC-Body byte-identisch zur Python-Lib", () => {
    expect(encodeRequestBody({ rpcparams: '{"username": "demo"}' })).toBe(
      "eqap=dz%3AKypILkgsSswttlU1d1I1MiotTi3KS8xNBTJVjR1VjQyAjJTU3HwQ39wFAA%3D%3D&eqacs=448ebedfa881a565068ef932c4a9884e9c998c8d&eqaz=1",
    );
  });

  it("dekodiert Antworten wie decode_response", () => {
    expect(decodeResponse('{"a":1}')).toBe('{"a":1}');
    expect(decodeResponse("eqwd:eyJhIjoyfQ==")).toBe('{"a":2}');
    expect(decodeResponse("eqz:eyJiIjozfQ==")).toBe('{"b":3}');
  });

  it("zieht userhome-Daten und gsec-Hash aus der Loginseite", () => {
    const html = '<html><body><script>userhome({"subdomain":"demo","id":7});\n</script><script>ASC.gsechash="abc123";</script></body></html>';
    expect(parseUserhome(html)).toEqual({ data: { subdomain: "demo", id: 7 }, gsecHash: "abc123" });
    expect(() => parseUserhome("<html>kein Login</html>")).toThrow();
  });

  it("parst userhome wie Python trotz Nachbar-Content (rsplit-Semantik)", () => {
    const html = '<script>userhome({"a":1});</script><script>var x = foo();</script>';
    expect(parseUserhome(html)).toEqual({ data: { a: 1 }, gsecHash: null });
  });

  it("zieht 2FA-Felder und CSRF-Token aus den Formularseiten", () => {
    const twofa = '<input name="csrfauth" value="csrf-1"><input name="au" value="au-2"><input name="gu" value="gu-3">';
    expect(extractTwoFactorFields(twofa)).toEqual({ csrf: "csrf-1", au: "au-2", gu: "gu-3" });
    expect(extractTwoFactorFields("<html>leer</html>")).toBeNull();
    expect(extractCsrfToken('{"csrftoken":"tok-9"}')).toBe("tok-9");
    expect(extractCsrfToken("<html>leer</html>")).toBeNull();
  });
});
