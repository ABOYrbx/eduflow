import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Post, Req, UseGuards } from "@nestjs/common";
import type { Request } from "express";
import type { AuthenticatedRequest } from "./access-token.guard";
import { AccessTokenGuard } from "./access-token.guard";
import { AuthService } from "./auth.service";

@Controller()
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @HttpCode(HttpStatus.OK)
  @Post("auth/login") login(@Body() body: unknown, @Req() request: Request) {
    const trustProxy = ["1", "true", "yes", "on"].includes((process.env.EDUFLOW_TRUST_PROXY ?? "").toLowerCase());
    const forwarded = trustProxy ? request.headers["x-forwarded-for"] : undefined;
    const forwardedIp = Array.isArray(forwarded) ? forwarded[0] : typeof forwarded === "string" ? forwarded.split(",")[0]?.trim() : undefined;
    return this.auth.login(body, forwardedIp || request.socket.remoteAddress || "unknown");
  }
  @HttpCode(HttpStatus.OK)
  @Post("auth/2fa") twoFactor(@Body() body: unknown, @Req() request: Request) { return this.auth.finishTwoFactor(body, request.socket.remoteAddress || "unknown"); }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK)
  @Post("auth/logout") logout(@Req() request: AuthenticatedRequest) { return this.auth.logout(request.authClaims); }
  @HttpCode(HttpStatus.OK)
  @Post("auth/refresh") refresh(@Req() request: Request, @Body() body: unknown) {
    const supplied = typeof body === "object" && body !== null && "refresh_token" in body
      ? (body as { refresh_token?: unknown }).refresh_token : undefined;
    const bearer = /^Bearer\s+(.+)$/i.exec(request.headers.authorization ?? "")?.[1];
    const token = typeof supplied === "string" && supplied ? supplied : bearer;
    if (!token) return this.auth.refresh("");
    return this.auth.refresh(token);
  }
  @UseGuards(AccessTokenGuard)
  @Get("me") me(@Req() request: AuthenticatedRequest) { return this.auth.current(request.authClaims); }
  @UseGuards(AccessTokenGuard)
  @Get("devices") devices(@Req() request: AuthenticatedRequest) { return this.auth.devices(request.authClaims); }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK)
  @Post("devices") createDevice(@Req() request: AuthenticatedRequest, @Body() body: unknown) { return this.auth.createDevice(request.authClaims, body); }
  @UseGuards(AccessTokenGuard)
  @Delete("devices/:id") revoke(@Req() request: AuthenticatedRequest, @Param("id") id: string) { return this.auth.revokeDevice(request.authClaims, id); }
}
