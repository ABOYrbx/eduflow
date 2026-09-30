import { Controller, Get } from "@nestjs/common";
import { t } from "../i18n";

@Controller()
export class SystemController {
  @Get("health")
  health(): { status: "ok"; version: "v1" } {
    return { status: "ok", version: "v1" };
  }

  @Get("openapi.json")
  openapi(): Record<string, unknown> {
    const get = (summary: string, secure = true) => ({ summary, responses: { "200": { description: "OK" }, "400": { description: t("docs.validationDescription") }, "401": { description: t("docs.authDescription") } }, ...(secure ? { security: [{ bearerAuth: [] }] } : {}) });
    const post = (summary: string, secure = true) => ({ ...get(summary, secure), requestBody: { required: false, content: { "application/json": { schema: { type: "object" } } } } });
    const paths: Record<string, unknown> = {
      "/api/v1/health": { get: get(t("docs.liveness"), false) }, "/api/v1/openapi.json": { get: get(t("docs.apiContract"), false) },
      "/api/v1/auth/login": { post: post(t("docs.login"), false) }, "/api/v1/auth/2fa": { post: post(t("docs.quit2fa"), false) },
      "/api/v1/auth/logout": { post: post(t("docs.logout")) }, "/api/v1/auth/refresh": { post: post(t("docs.rotateToken"), false) },
      "/api/v1/me": { get: get(t("docs.myAccount")) }, "/api/v1/devices": { get: get(t("docs.myDevices")), post: post(t("docs.createDeviceToken")) }, "/api/v1/devices/{id}": { delete: get(t("docs.revokeDevice")) }, "/api/v1/devices/revoke-others": { post: post(t("docs.revokeOtherDevices")) },
      "/api/v1/messages": { get: get(t("docs.messages")) }, "/api/v1/messages/{id}/thread": { get: get(t("docs.thread")) },
      "/api/v1/messages/read": { post: post(t("docs.markRead")) }, "/api/v1/recipients": { get: get(t("docs.recipients")) },
      "/api/v1/messages/send": { post: post(t("docs.sendMessage")) }, "/api/v1/messages/{id}/reply": { post: post(t("docs.replyMessage")) },
      "/api/v1/messages/download-token": { post: post(t("docs.issueDownloadToken")) }, "/api/v1/messages/{id}/attachments/{idx}": { get: get(t("docs.loadAttachment")) },
      "/api/v1/homework": { get: get(t("docs.homeworkList")) }, "/api/v1/homework/{id}/done": { post: post(t("docs.doHomework")) },
      "/api/v1/homework/{id}/trash": { post: post(t("docs.trashHomework")) },
      "/api/v1/timetable/day": { get: get(t("docs.timetableDay")) }, "/api/v1/timetable/week": { get: get(t("docs.timetableWeek")) },
      "/api/v1/substitutions/week": { get: get(t("docs.substitutions")) }, "/api/v1/school/agenda": { get: get(t("docs.agenda")) },
      "/api/v1/grades": { get: get(t("docs.grades")) },
      "/api/v1/wetter": { get: get(t("docs.weather")) }, "/api/v1/wetter/suche": { get: get(t("docs.weatherSearch")) },
      "/api/v1/settings": { get: get(t("docs.readSettings")), put: post(t("docs.saveSettings")) }, "/api/v1/cache-clear": { post: post(t("docs.clearCache")) },
    };
    return { openapi: "3.0.0", info: { title: "EduFlow API", version: "v1" }, servers: [{ url: "/api/v1" }], components: { securitySchemes: { bearerAuth: { type: "http", scheme: "bearer" } } }, paths };
  }
}
