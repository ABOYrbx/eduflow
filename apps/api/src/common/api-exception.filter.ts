import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from "@nestjs/common";
import type { Response } from "express";
import { t } from "../i18n";

const KNOWN_CODES = new Set(["VALIDATION", "TOKEN_INVALID", "TOKEN_EXPIRED", "PENDING_INVALID", "INVALID_CODE",
  "BAD_CREDENTIALS", "EDUPAGE_2FA", "CAPTCHA_REQUIRED", "NOT_FOUND", "RATE_LIMITED", "CONFIG_MISSING", "UPSTREAM"]);

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const status = exception instanceof HttpException ? exception.getStatus() : HttpStatus.BAD_GATEWAY;
    const body = exception instanceof HttpException ? exception.getResponse() : null;
    const record = typeof body === "object" && body !== null ? body as Record<string, unknown> : {};
    const code = typeof record.code === "string" && KNOWN_CODES.has(record.code)
      ? record.code : status === HttpStatus.BAD_REQUEST ? "VALIDATION"
        : status === HttpStatus.NOT_FOUND ? "NOT_FOUND"
          : status === HttpStatus.UNAUTHORIZED ? "TOKEN_INVALID"
            : status === HttpStatus.TOO_MANY_REQUESTS ? "RATE_LIMITED" : "UPSTREAM";
    const fallback = status === 400 ? t("common.badRequest") : status === 404 ? t("common.notFound") : t("common.failed");
    const message = typeof record.error === "string" ? record.error : fallback;
    response.status(status).json({ error: message, code });
  }
}
