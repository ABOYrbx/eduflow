import { createHash } from "node:crypto";
import { AuthService } from "./auth.service";
import { EdupageClient } from "../edupage/client";
import { BadCredentialsError, CaptchaError } from "../edupage/errors";
import type { FetchImpl } from "../edupage/session";

const VAULT_KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
const USERHOME = '<html><script>userhome({"subdomain":"demo","id":7});</script><script>ASC.gsechash="gsec-1";</script></html>';
const TWOFA = '<input name="csrfauth" value="csrf-1"><input name="au" value="au-2"><input name="gu" value="gu-3">';
const sha256 = (value: string): string => createHash("sha256").update(value).digest("hex");

interface Route { status: number; url: string; text: string; setCookie?: string[]; }

function stubFetch(routes: Record<string, Route>): FetchImpl {
  return async (url, init) => {
    const route = routes[`${init.method} ${url}`];
    if (!route) throw new Error(`unerwarteter Request: ${init.method} ${url}`);
    return { status: route.status, url: route.url, headers: { get: () => null, getSetCookie: () => route.setCookie ?? [] }, text: async () => route.text, arrayBuffer: async () => new ArrayBuffer(0) };
  };
}

const rpcLogin = (redirect: string): Record<string, Route> => ({
  "GET https://demo.edupage.org/login/?cmd=MainLogin": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin", text: "<html>start</html>" },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=getToken", text: '{"token":"tok-1"}' },
  "POST https://demo.edupage.org/login/?cmd=MainLogin&akcia=login": { status: 200, url: "https://demo.edupage.org/login/?cmd=MainLogin&akcia=login", text: `{"redirectUrl":"${redirect}","err":{}}` },
  "GET https://demo.edupage.org/user": { status: 200, url: "https://demo.edupage.org/user", text: USERHOME },
});

const twoFactorFinish: Record<string, Route> = {
  "GET https://demo.edupage.org/login/twofactor?sn=0": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=0", text: "<html>weiter</html>" },
  "GET https://demo.edupage.org/login/twofactor?sn=1": { status: 200, url: "https://demo.edupage.org/login/twofactor?sn=1", text: TWOFA },
  "POST https://demo.edupage.org/login/edubarLogin.php": { status: 200, url: "https://demo.edupage.org/login/edubarLogin.php", text: "<script>window.location = gu;</script>", setCookie: ["PHPSESSID=sess-9; path=/"] },
};

describe("AuthService (echter EduPage-Anbieter, Python-Parität)", () => {
  const account = { id: "acct_9", subdomain: "demo", username: "demo" };
  const oldProvider = process.env.EDUFLOW_PROVIDER;
  const oldKey = process.env.CREDENTIAL_ENCRYPTION_KEY;
  let tokens: Record<string, any>[];
  let pendings: Record<string, any>[];
  let service: AuthService;

  const prisma = {
    userAccount: {
      upsert: jest.fn(async ({ create }: { create: Record<string, unknown> }) => ({ id: account.id, ...create })),
      findUnique: jest.fn(async () => account),
    },
    apiToken: {
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => { const row = { id: `row_${tokens.length}`, createdAt: new Date(), revokedAt: null, ...data }; tokens.push(row); return row; }),
      findUnique: jest.fn(async ({ where }: { where: Record<string, string> }) => tokens.find((row) => row.accessTokenHash === where.accessTokenHash) ?? null),
      findMany: jest.fn(async () => [...tokens]),
      update: jest.fn(async ({ where, data }: { where: Record<string, string>; data: Record<string, unknown> }) => {
        const row = tokens.find((item) => item.id === where.id);
        if (!row) throw new Error("Token fehlt");
        Object.assign(row, data);
        return row;
      }),
      updateMany: jest.fn(async ({ where, data }: { where: Record<string, any>; data: Record<string, unknown> }) => {
        const hit = tokens.filter((row) => row.accessTokenHash === where.accessTokenHash && row.revokedAt === null);
        hit.forEach((row) => Object.assign(row, data));
        return { count: hit.length };
      }),
    },
    pendingSecondFactor: {
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => { const row = { id: `p_${pendings.length}`, consumedAt: null, ...data }; pendings.push(row); return row; }),
      findUnique: jest.fn(async ({ where }: { where: Record<string, string> }) => pendings.find((row) => row.opaqueTokenHash === where.opaqueTokenHash) ?? null),
      updateMany: jest.fn(async ({ where, data }: { where: Record<string, any>; data: Record<string, unknown> }) => {
        const hit = pendings.filter((row) => row.id === where.id && row.consumedAt === null);
        hit.forEach((row) => Object.assign(row, data));
        return { count: hit.length };
      }),
    },
    credentialVault: {
      upsert: jest.fn(async () => ({})),
      findUnique: jest.fn(async () => null),
    },
  };

  const factoryFor = (routes: Record<string, Route>) => () => new EdupageClient(stubFetch(routes));

  beforeAll(() => {
    delete process.env.EDUFLOW_PROVIDER;
    process.env.CREDENTIAL_ENCRYPTION_KEY = VAULT_KEY;
  });
  afterAll(() => {
    if (oldProvider === undefined) delete process.env.EDUFLOW_PROVIDER;
    else process.env.EDUFLOW_PROVIDER = oldProvider;
    if (oldKey === undefined) delete process.env.CREDENTIAL_ENCRYPTION_KEY;
    else process.env.CREDENTIAL_ENCRYPTION_KEY = oldKey;
  });
  beforeEach(() => {
    tokens = [];
    pendings = [];
    jest.clearAllMocks();
    service = new AuthService(prisma as never, null as never, factoryFor(rpcLogin("/user")));
  });

  it("meldet an und antwortet wie Python (ok + Ablaufformat)", async () => {
    const result = await service.login({ username: "demo", password: "geheim", subdomain: "demo", device: "Mac" });
    expect(result).toMatchObject({ status: "ok", subdomain: "demo", username: "demo" });
    const token = (result as { token: string }).token;
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect((result as { expires: string }).expires).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
    expect(prisma.apiToken.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ accessTokenHash: sha256(token) }) }));
    expect(prisma.credentialVault.upsert).toHaveBeenCalled();
    await expect(service.authenticate(token)).resolves.toMatchObject({ sub: account.id, tokenUse: "access" });
  });

  it("startet 2FA mit Python-Text und -Ablauf", async () => {
    service = new AuthService(prisma as never, null as never, factoryFor({ ...rpcLogin("/login/twofactor?sn=0"), ...twoFactorFinish }));
    const result = await service.login({ username: "demo", password: "geheim", subdomain: "demo" });
    expect(result).toMatchObject({ status: "2fa_required", message: "Enter the two-factor code from email or app and send it to /auth/2fa." });
    expect((result as { pending_token: string }).pending_token).toMatch(/^[0-9a-f]{32}$/);
  });

  it("tauscht Zwischen-Token und Code gegen ein Token", async () => {
    service = new AuthService(prisma as never, null as never, factoryFor({ ...rpcLogin("/login/twofactor?sn=0"), ...twoFactorFinish }));
    const started = await service.login({ username: "demo", password: "geheim", subdomain: "demo" }) as { pending_token: string };
    const done = await service.finishTwoFactor({ pending_token: started.pending_token, code: "123456" }) as { status: string; token: string };
    expect(done.status).toBe("ok");
    expect(done.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(prisma.pendingSecondFactor.updateMany).toHaveBeenCalled();
  });

  it("mappt EduPage-Fehler auf BAD_CREDENTIALS und CAPTCHA_REQUIRED", async () => {
    const bad = new AuthService(prisma as never, null as never, () => ({ login: async () => { throw new BadCredentialsError(); } }) as never);
    await expect(bad.login({ username: "x", password: "y" })).rejects.toMatchObject({ response: { code: "BAD_CREDENTIALS", error: "Wrong username, password or subdomain." } });
    const captcha = new AuthService(prisma as never, null as never, () => ({ login: async () => { throw new CaptchaError(); } }) as never);
    await expect(captcha.login({ username: "x", password: "y" })).rejects.toMatchObject({ response: { code: "CAPTCHA_REQUIRED" } });
  });

  it("lehnt falschen 2FA-Code mit INVALID_CODE ab", async () => {
    const failing: Record<string, Route> = {
      ...rpcLogin("/login/twofactor?sn=0"),
      ...twoFactorFinish,
      "POST https://demo.edupage.org/login/edubarLogin.php": { status: 200, url: "https://demo.edupage.org/login/edubarLogin.php", text: "<html>Fehler</html>" },
    };
    service = new AuthService(prisma as never, null as never, factoryFor(failing));
    const started = await service.login({ username: "demo", password: "geheim", subdomain: "demo" }) as { pending_token: string };
    await expect(service.finishTwoFactor({ pending_token: started.pending_token, code: "000000" }))
      .rejects.toMatchObject({ response: { code: "INVALID_CODE", error: "The code was not accepted. Please try again." } });
  });

  it("unterscheidet abgelaufene und unbekannte Tokens", async () => {
    const login = await service.login({ username: "demo", password: "geheim", subdomain: "demo" }) as { token: string };
    const first = tokens[0];
    if (!first) throw new Error("kein Token");
    first.accessExpiresAt = new Date(Date.now() - 1000);
    await expect(service.authenticate(login.token)).rejects.toMatchObject({ response: { code: "TOKEN_EXPIRED", error: "Token expired. Please sign in again." } });
    await expect(service.authenticate("unbekannt")).rejects.toMatchObject({ response: { code: "TOKEN_INVALID" } });
  });

  it("listet Geräte im Python-Format und widerruft per Hash", async () => {
    const login = await service.login({ username: "demo", password: "geheim", subdomain: "demo", device: "Mac" }) as { token: string };
    const listed = await service.authenticate(login.token).then((claims) => service.devices(claims)) as { items: Record<string, unknown>[]; total: number };
    expect(listed.total).toBe(1);
    expect(listed.items[0]).toMatchObject({ id: sha256(login.token), device: "Mac" });
    expect(listed.items[0]?.short).toMatch(/^…[0-9a-f]{6}$/);
    const claims = await service.authenticate(login.token);
    await expect(service.revokeDevice(claims, "")).rejects.toMatchObject({ response: { code: "VALIDATION" } });
    await expect(service.revokeDevice(claims, "falsch")).rejects.toMatchObject({ response: { code: "NOT_FOUND" } });
    await expect(service.revokeDevice(claims, sha256(login.token))).resolves.toMatchObject({ status: "ok" });
  });
});
