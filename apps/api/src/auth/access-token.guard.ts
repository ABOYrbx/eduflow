import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import type { Request } from "express";
import { t } from "../i18n";
import { AuthClaims, AuthService } from "./auth.service";

export interface AuthenticatedRequest extends Request { authClaims: AuthClaims; }

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = request.headers.authorization ?? "";
    const attachment = /\/messages\/\d+\/attachments\/\d+$/.test(request.path);
    const query = request.query as Record<string, unknown>;
    if (attachment && typeof query.dl === "string" && query.dl) return true;
    const queryToken = attachment && typeof query.token === "string" ? query.token : "";
    const match = /^Bearer\s+(.+)$/i.exec(header);
    const token = match?.[1] || queryToken;
    if (!token) throw new UnauthorizedException({ error: t("auth.tokenMissing"), code: "TOKEN_INVALID" });
    request.authClaims = await this.auth.authenticate(token);
    return true;
  }
}
