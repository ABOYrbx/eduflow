const KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";

describe("vault (AES-256-GCM, CredentialVault-Format)", () => {
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;

  beforeEach(() => {
    process.env.CREDENTIAL_ENCRYPTION_KEY = KEY;
    jest.resetModules();
  });
  afterAll(() => {
    if (oldKey === undefined) delete process.env.CREDENTIAL_ENCRYPTION_KEY;
    else process.env.CREDENTIAL_ENCRYPTION_KEY = oldKey;
  });

  it("ver- und entschlüsselt Roundtrip", async () => {
    const { sealPassword, openPassword } = await import("./vault");
    const sealed = sealPassword("Schulpasswort-123");
    expect(sealed.ciphertext.length).toBeGreaterThan(16);
    expect(sealed.nonce).toHaveLength(12);
    expect(openPassword(sealed)).toBe("Schulpasswort-123");
  });

  it("scheitert ohne Schlüssel mit CONFIG_MISSING", async () => {
    delete process.env.CREDENTIAL_ENCRYPTION_KEY;
    const { sealPassword } = await import("./vault");
    try {
      sealPassword("x");
      throw new Error("kein Fehler");
    } catch (error) {
      const response = (error as { getStatus?: () => number; getResponse?: () => unknown }).getResponse?.() as Record<string, unknown>;
      expect((error as { getStatus?: () => number }).getStatus?.()).toBe(503);
      expect(response).toMatchObject({ code: "CONFIG_MISSING" });
    }
  });
});
