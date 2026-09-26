import { createHash, randomBytes, randomUUID } from "node:crypto";
import { Injectable, UnauthorizedException, BadRequestException, ForbiddenException, NotFoundException, HttpException, Optional } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { PrismaService } from "../prisma/prisma.service";
import { EdupageClient, TwoFactorFields } from "../edupage/client";
import { BadCredentialsError, CaptchaError, SecondFactorFailedError } from "../edupage/errors";
import { formatDateTime, hashToken, newOpaqueToken, opaqueExpiry } from "../edupage/tokens";
import { openPassword, sealPassword } from "../edupage/vault";

const sha256 = (value: string): string => createHash("sha256").update(value).digest("hex");
const bearerError = (): UnauthorizedException => new UnauthorizedException({ error: "Token ungültig.", code: "TOKEN_INVALID" });

export interface AuthClaims { sub: string; jti: string; tokenUse: "access" | "refresh"; }
const isExpired = (error: unknown): boolean => error instanceof Error && error.name === "TokenExpiredError";

/** Prisma-`Bytes` brauchen `Uint8Array<ArrayBuffer>` (Node-Buffer kopieren). */
const bytesOf = (value: Uint8Array): Uint8Array<ArrayBuffer> => {
  const copy = new Uint8Array(value.length);
  copy.set(value);
  return copy;
};

interface EdupageChallenge {
  kind: "edupage";
  subdomain: string;
  username: string;
  device: string;
  fields: TwoFactorFields;
  cookies: Record<string, string>;
}

@Injectable()
export class AuthService {
  private readonly loginAttempts = new Map<string, number[]>();
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    @Optional() private readonly clientFactory: () => EdupageClient = () => new EdupageClient(),
  ) {
    this.clientFactory = clientFactory ?? (() => new EdupageClient());
  }

  private isFake(): boolean {
    return process.env.EDUFLOW_PROVIDER === "fake";
  }

  private checkLoginRate(ip: string): void {
    const now = Date.now(); const current = (this.loginAttempts.get(ip) ?? []).filter((time) => now - time < 10 * 60_000);
    current.push(now); this.loginAttempts.set(ip, current.slice(-40));
    if (current.length > 20) throw new HttpException({ error: "Zu viele Versuche. Bitte später erneut versuchen.", code: "RATE_LIMITED" }, 429);
  }

  private async issue(account: { id: string; subdomain: string; username: string }, device: string) {
    const tokenId = randomUUID();
    const access = await this.jwt.signAsync({ sub: account.id, jti: tokenId, tokenUse: "access" } satisfies AuthClaims, { expiresIn: "30d" });
    const refresh = await this.jwt.signAsync({ sub: account.id, jti: tokenId, tokenUse: "refresh" } satisfies AuthClaims, { expiresIn: "30d" });
    const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await this.prisma.apiToken.create({ data: {
      id: tokenId, accountId: account.id, accessTokenHash: sha256(access), refreshTokenHash: sha256(refresh),
      deviceName: device.slice(0, 80), accessExpiresAt: expires, refreshExpiresAt: expires,
    } });
    return { status: "ok", token: access, refresh_token: refresh, expires: expires.toISOString(),
      refresh_expires: expires.toISOString(), subdomain: account.subdomain, username: account.username };
  }

  // ------------------------------------------------ EduPage-Anbieter (Paket N-A)

  private edupageError(error: unknown): HttpException {
    if (error instanceof BadCredentialsError) {
      return new UnauthorizedException({ error: "Falscher Benutzername, Passwort oder Subdomain.", code: "BAD_CREDENTIALS" });
    }
    if (error instanceof CaptchaError) {
      return new ForbiddenException({ error: "EduPage verlangt ein Captcha. Bitte einmal im Browser anmelden, dann erneut versuchen.", code: "CAPTCHA_REQUIRED" });
    }
    const detail = error instanceof Error ? error.message : String(error);
    return new HttpException({ error: `Anmeldung fehlgeschlagen: ${detail}`, code: "UPSTREAM" }, 502);
  }

  private async issueOpaque(account: { id: string; subdomain: string; username: string }, device: string) {
    const token = newOpaqueToken();
    const expires = opaqueExpiry();
    const row = await this.prisma.apiToken.create({ data: {
      accountId: account.id, accessTokenHash: hashToken(token), refreshTokenHash: null,
      deviceName: device.slice(0, 80), accessExpiresAt: expires, refreshExpiresAt: null,
    } });
    void row;
    return { status: "ok", token, expires: formatDateTime(expires), subdomain: account.subdomain, username: account.username };
  }

  private async rememberAccount(subdomain: string, username: string, password: string) {
    const account = await this.prisma.userAccount.upsert({
      where: { subdomain_username: { subdomain, username } },
      update: {}, create: { subdomain, username },
    });
    const sealed = sealPassword(password);
    await this.prisma.credentialVault.upsert({
      where: { accountId: account.id },
      update: { ciphertext: bytesOf(sealed.ciphertext), nonce: bytesOf(sealed.nonce) },
      create: { accountId: account.id, ciphertext: bytesOf(sealed.ciphertext), nonce: bytesOf(sealed.nonce) },
    });
    return account;
  }

  private async vaultPassword(accountId: string): Promise<string> {
    const sealed = await this.prisma.credentialVault.findUnique({ where: { accountId } });
    if (!sealed) throw bearerError();
    try {
      return openPassword({ ciphertext: Buffer.from(sealed.ciphertext), nonce: Buffer.from(sealed.nonce) });
    } catch (error) {
      if (error instanceof HttpException) throw error;
      throw bearerError();
    }
  }

  private async edupageLogin(username: string, password: string, subdomain: string, device: string) {
    const cleanDevice = device.slice(0, 80);
    let result;
    try {
      result = await this.clientFactory().login(username, password, subdomain);
    } catch (error) {
      throw this.edupageError(error);
    }
    if (result.outcome === "twofactor") {
      const account = await this.rememberAccount(result.subdomain, username, password);
      const pending = randomBytes(16).toString("hex");
      const challenge: EdupageChallenge = { kind: "edupage", subdomain: result.subdomain, username,
        device: cleanDevice, fields: result.fields, cookies: result.cookies };
      await this.prisma.pendingSecondFactor.create({ data: {
        accountId: account.id, opaqueTokenHash: hashToken(pending), challenge: bytesOf(Buffer.from(JSON.stringify(challenge))),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      } });
      return { status: "2fa_required", pending_token: pending,
        message: "Zwei-Faktor-Code aus E-Mail oder App eingeben und an /auth/2fa senden." };
    }
    const account = await this.rememberAccount(result.subdomain, username, password);
    return this.issueOpaque({ id: account.id, subdomain: result.subdomain, username }, cleanDevice);
  }

  private async authenticateOpaque(rawToken: string): Promise<AuthClaims> {
    const row = await this.prisma.apiToken.findUnique({ where: { accessTokenHash: hashToken(rawToken) } });
    if (!row || row.revokedAt) {
      throw new UnauthorizedException({ error: "Ungültiges oder fehlendes Token.", code: "TOKEN_INVALID" });
    }
    if (row.accessExpiresAt <= new Date()) {
      throw new UnauthorizedException({ error: "Token ist abgelaufen. Bitte erneut anmelden.", code: "TOKEN_EXPIRED" });
    }
    await this.prisma.apiToken.update({ where: { id: row.id }, data: { lastUsedAt: new Date() } });
    return { sub: row.accountId, jti: row.id, tokenUse: "access" };
  }

  private async edupageRefresh(rawToken: string) {
    const claims = await this.authenticateOpaque(rawToken);
    const account = await this.prisma.userAccount.findUnique({ where: { id: claims.sub } });
    if (!account) throw bearerError();
    const password = await this.vaultPassword(account.id);
    let result;
    try {
      result = await this.clientFactory().login(account.username, password, account.subdomain);
    } catch (error) {
      throw this.edupageError(error);
    }
    if (result.outcome === "twofactor") {
      throw new UnauthorizedException({ error: "Sitzung erfordert erneut 2FA. Bitte erneut über /auth/login anmelden.", code: "EDUPAGE_2FA" });
    }
    const previous = await this.prisma.apiToken.findUnique({ where: { accessTokenHash: hashToken(rawToken) } });
    const issued = await this.issueOpaque(
      { id: account.id, subdomain: result.subdomain, username: account.username }, previous?.deviceName ?? "");
    await this.prisma.apiToken.updateMany({ where: { accessTokenHash: hashToken(rawToken), revokedAt: null },
      data: { revokedAt: new Date(), refreshTokenHash: null } });
    return issued;
  }

  async login(input: unknown, clientIp = "unknown") {
    this.checkLoginRate(clientIp);
    if (typeof input !== "object" || input === null || Array.isArray(input)) {
      throw new BadRequestException({ error: "Ungültige Anfrage (JSON erwartet).", code: "VALIDATION" });
    }
    const body = input as Record<string, unknown>;
    const username = typeof body.username === "string" ? body.username.trim() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const rawSubdomain = typeof body.subdomain === "string" ? body.subdomain.trim().toLowerCase() : "";
    const device = typeof body.device === "string" ? body.device : "";
    if (!username || !password) throw new BadRequestException({ error: "Bitte Benutzername und Passwort angeben.", code: "VALIDATION" });

    if (!this.isFake()) return this.edupageLogin(username, password, rawSubdomain || "login1", device);
    const subdomain = rawSubdomain || "demo";
    const validUser = username === "demo" || username === "demo-2fa";
    if (!validUser || password !== "demo") throw new UnauthorizedException({ error: "Falscher Benutzername, Passwort oder Subdomain.", code: "BAD_CREDENTIALS" });
    const account = await this.prisma.userAccount.upsert({
      where: { subdomain_username: { subdomain, username } },
      update: {}, create: { subdomain, username },
    });
    if (username === "demo-2fa") {
      const pending = randomBytes(32).toString("hex");
      const challenge = Buffer.from(JSON.stringify({ device }));
      await this.prisma.pendingSecondFactor.create({ data: {
        accountId: account.id, opaqueTokenHash: sha256(pending), challenge,
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      } });
      return { status: "2fa_required", pending_token: pending, message: "Demo-Code 123456 eingeben." };
    }
    return this.issue(account, device);
  }

  async finishTwoFactor(input: unknown, clientIp = "unknown") {
    this.checkLoginRate(clientIp);
    if (typeof input !== "object" || input === null || Array.isArray(input)) throw new BadRequestException({ error: "Ungültige Anfrage.", code: "VALIDATION" });
    const body = input as Record<string, unknown>;
    const token = typeof body.pending_token === "string" ? body.pending_token : "";
    const code = typeof body.code === "string" ? body.code : "";
    if (!token || !code) throw new BadRequestException({ error: "Bitte Zwischen-Token und Code angeben.", code: "VALIDATION" });
    const pending = await this.prisma.pendingSecondFactor.findUnique({ where: { opaqueTokenHash: sha256(token) } });
    if (!pending || pending.consumedAt || pending.expiresAt <= new Date() || !pending.accountId) throw new UnauthorizedException({ error: "Zwischenschritt abgelaufen. Bitte erneut anmelden.", code: "PENDING_INVALID" });
    if (!this.isFake()) return this.edupageFinish(pending, code);
    if (code !== "123456") throw new UnauthorizedException({ error: "Der Code wurde nicht akzeptiert.", code: "INVALID_CODE" });
    const claimed = await this.prisma.pendingSecondFactor.updateMany({ where: { id: pending.id, consumedAt: null }, data: { consumedAt: new Date() } });
    if (claimed.count !== 1) throw new UnauthorizedException({ error: "Zwischenschritt abgelaufen. Bitte erneut anmelden.", code: "PENDING_INVALID" });
    const account = await this.prisma.userAccount.findUnique({ where: { id: pending.accountId } });
    if (!account) throw bearerError();
    const challenge = JSON.parse(Buffer.from(pending.challenge).toString("utf8")) as { device?: string };
    return this.issue(account, challenge.device ?? "");
  }

  private readEdupageChallenge(pending: { challenge: Uint8Array }): EdupageChallenge {
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(Buffer.from(pending.challenge).toString("utf8")) as unknown;
    } catch {
      parsed = null;
    }
    const candidate = parsed as Partial<EdupageChallenge> | null;
    if (!candidate || candidate.kind !== "edupage" || typeof candidate.subdomain !== "string"
      || typeof candidate.username !== "string" || typeof candidate.fields !== "object" || !candidate.fields
      || typeof candidate.cookies !== "object" || !candidate.cookies) {
      throw new UnauthorizedException({ error: "Zwischenschritt abgelaufen. Bitte erneut anmelden.", code: "PENDING_INVALID" });
    }
    return candidate as EdupageChallenge;
  }

  private async edupageFinish(pending: { id: string; accountId: string | null; challenge: Uint8Array }, code: string) {
    const challenge = this.readEdupageChallenge(pending);
    const client = this.clientFactory();
    client.loadCookies(challenge.subdomain, challenge.cookies);
    try {
      await client.finishTwoFactor(challenge.subdomain, challenge.fields, code, challenge.username);
    } catch (error) {
      if (error instanceof SecondFactorFailedError) {
        throw new UnauthorizedException({ error: "Der Code wurde nicht akzeptiert. Bitte erneut versuchen.", code: "INVALID_CODE" });
      }
      throw this.edupageError(error);
    }
    await this.prisma.pendingSecondFactor.updateMany({ where: { id: pending.id, consumedAt: null }, data: { consumedAt: new Date() } });
    const account = await this.prisma.userAccount.upsert({
      where: { subdomain_username: { subdomain: challenge.subdomain, username: challenge.username } },
      update: {}, create: { subdomain: challenge.subdomain, username: challenge.username },
    });
    return this.issueOpaque({ id: account.id, subdomain: challenge.subdomain, username: challenge.username }, challenge.device ?? "");
  }

  async current(claims: AuthClaims) {
    const account = await this.prisma.userAccount.findUnique({ where: { id: claims.sub }, select: { subdomain: true, username: true } });
    if (!account) throw bearerError();
    return account;
  }

  async createDevice(claims: AuthClaims, input: unknown) {
    if (typeof input !== "object" || input === null || Array.isArray(input)) {
      throw new BadRequestException({ error: "Ungültige Anfrage (JSON erwartet).", code: "VALIDATION" });
    }
    const body = input as Record<string, unknown>;
    if (body.device !== undefined && typeof body.device !== "string") {
      throw new BadRequestException({ error: "Der Gerätename muss Text sein.", code: "VALIDATION" });
    }
    const account = await this.prisma.userAccount.findUnique({ where: { id: claims.sub } });
    if (!account) throw bearerError();
    const deviceName = typeof body.device === "string" ? body.device.trim() : "";
    if (this.isFake()) return this.issue(account, deviceName);
    const password = await this.vaultPassword(account.id);
    let result;
    try {
      result = await this.clientFactory().login(account.username, password, account.subdomain);
    } catch (error) {
      throw this.edupageError(error);
    }
    if (result.outcome === "twofactor") {
      throw new UnauthorizedException({ error: "Sitzung erfordert erneut 2FA. Bitte erneut über /auth/login anmelden.", code: "EDUPAGE_2FA" });
    }
    return this.issueOpaque({ id: account.id, subdomain: result.subdomain, username: account.username }, deviceName);
  }

  async authenticate(rawToken: string): Promise<AuthClaims> {
    if (!this.isFake()) return this.authenticateOpaque(rawToken);
    try {
      const claims = await this.jwt.verifyAsync<AuthClaims>(rawToken);
      if (claims.tokenUse !== "access") throw bearerError();
      const row = await this.prisma.apiToken.findUnique({ where: { id: claims.jti } });
      if (!row || row.revokedAt || row.accessExpiresAt <= new Date() || row.accessTokenHash !== sha256(rawToken)) throw bearerError();
      await this.prisma.apiToken.update({ where: { id: row.id }, data: { lastUsedAt: new Date() } });
      return claims;
    } catch (error) {
      if (isExpired(error)) throw new UnauthorizedException({ error: "Token abgelaufen. Bitte erneut anmelden.", code: "TOKEN_EXPIRED" });
      throw bearerError();
    }
  }

  async refresh(rawToken: string) {
    if (!this.isFake()) return this.edupageRefresh(rawToken);
    let claims: AuthClaims;
    try { claims = await this.jwt.verifyAsync<AuthClaims>(rawToken); }
    catch (error) {
      if (isExpired(error)) throw new UnauthorizedException({ error: "Token abgelaufen. Bitte erneut anmelden.", code: "TOKEN_EXPIRED" });
      throw bearerError();
    }
    if (claims.tokenUse !== "refresh" && claims.tokenUse !== "access") throw bearerError();
    const row = await this.prisma.apiToken.findUnique({ where: { id: claims.jti } });
    const expectedHash = claims.tokenUse === "refresh" ? row?.refreshTokenHash : row?.accessTokenHash;
    const expiry = claims.tokenUse === "refresh" ? row?.refreshExpiresAt : row?.accessExpiresAt;
    if (!row || row.revokedAt || !expectedHash || expectedHash !== sha256(rawToken) || !expiry || expiry <= new Date()) throw bearerError();
    const account = await this.prisma.userAccount.findUnique({ where: { id: row.accountId } });
    if (!account) throw bearerError();
    const claimed = await this.prisma.apiToken.updateMany({ where: { id: row.id, revokedAt: null,
      ...(claims.tokenUse === "refresh" ? { refreshTokenHash: sha256(rawToken) } : { accessTokenHash: sha256(rawToken) }) },
      data: { revokedAt: new Date(), refreshTokenHash: null } });
    if (!claimed.count) throw bearerError();
    return this.issue(account, row.deviceName);
  }

  async logout(claims: AuthClaims) {
    await this.prisma.apiToken.updateMany({ where: { id: claims.jti, accountId: claims.sub, revokedAt: null }, data: { revokedAt: new Date(), refreshTokenHash: null } });
    return { status: "ok" };
  }

  async devices(claims: AuthClaims) {
    const rows = await this.prisma.apiToken.findMany({ where: { accountId: claims.sub }, orderBy: { createdAt: "desc" } });
    if (!this.isFake()) {
      const now = new Date();
      const items = rows
        .filter((row) => !row.revokedAt && row.accessExpiresAt > now)
        .map((row) => ({ id: row.accessTokenHash, short: `…${row.accessTokenHash.slice(-6)}`, device: row.deviceName,
          created: formatDateTime(row.createdAt), expires: formatDateTime(row.accessExpiresAt) }));
      return { items, total: items.length };
    }
    return { items: rows.map((row) => ({ id: row.accessTokenHash, device: row.deviceName,
      created: row.createdAt.toISOString(), expires: row.accessExpiresAt.toISOString(),
      current: row.id === claims.jti, revoked: row.revokedAt !== null })), total: rows.length };
  }

  async revokeDevice(claims: AuthClaims, id: string) {
    if (!this.isFake()) {
      const clean = (id ?? "").trim();
      if (!clean) throw new BadRequestException({ error: "Bitte Token-ID angeben.", code: "VALIDATION" });
      const result = await this.prisma.apiToken.updateMany({ where: { accountId: claims.sub, accessTokenHash: clean, revokedAt: null }, data: { revokedAt: new Date(), refreshTokenHash: null } });
      if (!result.count) throw new NotFoundException({ error: "Token nicht gefunden.", code: "NOT_FOUND" });
      return { status: "ok" };
    }
    const result = await this.prisma.apiToken.updateMany({ where: { accountId: claims.sub, accessTokenHash: id, revokedAt: null }, data: { revokedAt: new Date(), refreshTokenHash: null } });
    if (!result.count) throw new NotFoundException({ error: "Gerät nicht gefunden.", code: "NOT_FOUND" });
    return { status: "ok" };
  }
}
