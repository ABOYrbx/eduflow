import { JwtService } from "@nestjs/jwt";
import { AuthService } from "./auth.service";

describe("AuthService (fake EduPage provider)", () => {
  const account = { id: "acct_1", subdomain: "demo", username: "demo" };
  let tokenRow: Record<string, any> | null;
  let service: AuthService;
  let oldProvider: string | undefined;

  const prisma = {
    userAccount: {
      upsert: jest.fn(async () => account),
      findUnique: jest.fn(async () => account),
    },
    apiToken: {
      create: jest.fn(async ({ data }: { data: Record<string, any> }) => { tokenRow = { ...data, revokedAt: null }; return tokenRow; }),
      findUnique: jest.fn(async () => tokenRow),
      update: jest.fn(async () => tokenRow),
      updateMany: jest.fn(async () => { if (tokenRow) tokenRow.revokedAt = new Date(); return { count: 1 }; }),
      findMany: jest.fn(async () => tokenRow ? [tokenRow] : []),
    },
    pendingSecondFactor: { create: jest.fn(), findUnique: jest.fn(), updateMany: jest.fn() },
  };

  beforeAll(() => {
    oldProvider = process.env.EDUFLOW_PROVIDER;
    process.env.EDUFLOW_PROVIDER = "fake";
  });
  afterAll(() => {
    if (oldProvider === undefined) delete process.env.EDUFLOW_PROVIDER;
    else process.env.EDUFLOW_PROVIDER = oldProvider;
  });
  beforeEach(() => {
    tokenRow = null;
    jest.clearAllMocks();
    service = new AuthService(prisma as never, new JwtService({ secret: "test-secret-long-enough-to-sign-tokens" }));
  });

  it("issues a JWT pair and authenticates the access token against its stored hash", async () => {
    const result = await service.login({ username: "demo", password: "demo", device: "Test" });
    expect(result.status).toBe("ok");
    if (!("token" in result) || !("refresh_token" in result)) throw new Error("Expected a successful fake login");
    expect(result.token).toEqual(expect.any(String));
    expect(result.refresh_token).toEqual(expect.any(String));
    await expect(service.authenticate(result.token)).resolves.toMatchObject({ sub: account.id, tokenUse: "access" });
  });

  it("creates a separate device JWT pair for the signed-in account", async () => {
    const created = await service.createDevice({ sub: account.id, jti: "current", tokenUse: "access" }, { device: "  Pixel 8  " });
    expect(created.status).toBe("ok");
    if (!("token" in created) || !("refresh_token" in created)) throw new Error("Expected a successful device token response");
    expect(created.token).toEqual(expect.any(String));
    expect(created.refresh_token).toEqual(expect.any(String));
    expect(created).toMatchObject({ subdomain: account.subdomain, username: account.username });
    expect(prisma.apiToken.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ deviceName: "Pixel 8", accountId: account.id }) }));
    await expect(service.authenticate(created.token)).resolves.toMatchObject({ sub: account.id, tokenUse: "access" });
  });

  it("rejects malformed device token requests", async () => {
    await expect(service.createDevice({ sub: account.id, jti: "current", tokenUse: "access" }, null)).rejects.toMatchObject({ response: { code: "VALIDATION" } });
    await expect(service.createDevice({ sub: account.id, jti: "current", tokenUse: "access" }, { device: 123 })).rejects.toMatchObject({ response: { code: "VALIDATION" } });
  });

  it("rejects fake credentials", async () => {
    await expect(service.login({ username: "demo", password: "wrong" })).rejects.toMatchObject({
      response: { code: "BAD_CREDENTIALS" },
    });
  });

  it("attempts a real EduPage login outside the fake provider (no silent bypass)", async () => {
    const { BadCredentialsError } = await import("../edupage/errors");
    const real = new AuthService(prisma as never, new JwtService({ secret: "test-secret-long-enough-to-sign-tokens" }),
      () => ({ login: async () => { throw new BadCredentialsError(); } }) as never);
    process.env.EDUFLOW_PROVIDER = "unconfigured";
    await expect(real.login({ username: "demo", password: "demo" })).rejects.toMatchObject({
      response: { code: "BAD_CREDENTIALS" },
    });
    process.env.EDUFLOW_PROVIDER = "fake";
  });

  it("limits login attempts after twenty tries in the ten-minute window", async () => {
    for (let i = 0; i < 20; i++) await expect(service.login({}, "127.0.0.1")).rejects.toMatchObject({ response: { code: "VALIDATION" } });
    await expect(service.login({}, "127.0.0.1")).rejects.toMatchObject({ response: { code: "RATE_LIMITED" } });
  });
});
