import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Post, Put, Query, Req, Res, UnauthorizedException, UseGuards } from "@nestjs/common";
import type { Request, Response } from "express";
import { AccessTokenGuard, AuthenticatedRequest } from "../auth/access-token.guard";
import { AuthClaims, AuthService } from "../auth/auth.service";
import { DemoSchoolService } from "./demo-school.service";
import { EdupageDataService } from "../edupage/data";

interface AttachmentRequest extends Request { authClaims?: AuthClaims; }

const useFakeProvider = (): boolean => process.env.EDUFLOW_PROVIDER === "fake";

@Controller()
export class SchoolController {
  constructor(private readonly demo: DemoSchoolService, private readonly auth: AuthService, private readonly edupage: EdupageDataService) {}

  @UseGuards(AccessTokenGuard)
  @Get("messages") messages(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.messages(req.authClaims, query);
    return this.edupage.messages(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @Get("messages/:id/thread") thread(@Param("id") id: string, @Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.thread(req.authClaims, Number(id));
    return this.edupage.thread(req.authClaims, Number(id), query.refresh === "1");
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("messages/read") markRead(@Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.markMessagesRead(req.authClaims);
    return this.edupage.markRead(req.authClaims);
  }
  @UseGuards(AccessTokenGuard)
  @Get("recipients") recipients(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.recipients();
    return this.edupage.recipients(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("messages/send") send(@Body() body: unknown, @Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.sendMessage(body);
    return this.edupage.send(req.authClaims, body);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("messages/:id/reply") reply(@Param("id") id: string, @Body() body: unknown, @Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.reply(Number(id), body);
    return this.edupage.reply(req.authClaims, Number(id), body);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("messages/download-token") downloadToken(@Body() body: unknown, @Req() req: AuthenticatedRequest) {
    const input = typeof body === "object" && body !== null ? body as Record<string, unknown> : {};
    if (useFakeProvider()) return this.demo.issueDownload(req.authClaims, Number(input.event_id), Number(input.idx));
    return this.edupage.downloadToken(req.authClaims, body);
  }

  @Get("messages/:id/attachments/:idx")
  async attachment(@Param("id") id: string, @Param("idx") idx: string, @Query("dl") dl: string | undefined, @Query("token") token: string | undefined, @Req() req: AttachmentRequest, @Res() res: Response) {
    const eventId = Number(id); const index = Number(idx);
    if (!useFakeProvider()) {
      const bearer = /^Bearer\s+(.+)$/i.exec(req.headers.authorization ?? "")?.[1];
      const queryToken = !bearer && !dl && token ? token : undefined;
      const file = dl
        ? await this.edupage.attachmentByDl(dl, eventId, index)
        : await this.edupage.attachmentByClaims(
          req.authClaims ?? (bearer || queryToken ? await this.auth.authenticate((bearer ?? queryToken) as string) : (() => { throw new UnauthorizedException({ error: "Ungültiges oder fehlendes Token.", code: "TOKEN_INVALID" }); })()),
          eventId, index);
      res.setHeader("Content-Type", file.contentType);
      res.setHeader("Content-Disposition", `attachment; filename="${file.filename.replace(/[\r\n"\\]/g, "_")}"`);
      res.status(HttpStatus.OK).send(file.bytes);
      return;
    }
    const bearer = /^Bearer\s+(.+)$/i.exec(req.headers.authorization ?? "")?.[1];
    const accessQueryToken = !bearer && !dl && token ? token : undefined;
    const resolvedClaims = req.authClaims ?? (bearer ? await this.auth.authenticate(bearer) : accessQueryToken ? await this.auth.authenticate(accessQueryToken) : undefined);
    const file = this.demo.attachment(resolvedClaims, eventId, index, dl);
    res.setHeader("Content-Type", "application/octet-stream");
    res.setHeader("Content-Disposition", `attachment; filename="${file.filename.replace(/[\r\n"\\]/g, "_")}"`);
    res.status(HttpStatus.OK).send(file.content);
  }

  @UseGuards(AccessTokenGuard)
  @Get("homework") homework(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.homework(req.authClaims, query);
    return this.edupage.homeworkList(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("homework/:id/done") homeworkDone(@Param("id") id: string, @Body() body: unknown, @Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.homeworkChange(req.authClaims, id, "done", body);
    return this.edupage.homeworkDone(req.authClaims, id, body);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("homework/:id/trash") homeworkTrash(@Param("id") id: string, @Body() body: unknown, @Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.homeworkChange(req.authClaims, id, "trash", body);
    return this.edupage.homeworkTrash(req.authClaims, id, body);
  }
  @UseGuards(AccessTokenGuard)
  @Get("timetable/day") timetableDay(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.timetableDay(query);
    return this.edupage.timetableDay(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @Get("timetable/week") timetableWeek(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.timetableWeek(query);
    return this.edupage.timetableWeek(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @Get("substitutions/week") substitutions(@Query() query: Record<string, unknown>) { return this.demo.substitutions(query); }
  @UseGuards(AccessTokenGuard)
  @Get("school/agenda") agenda(@Query() query: Record<string, unknown>) { return this.demo.agenda(query); }
  @UseGuards(AccessTokenGuard)
  @Get("grades") grades(@Req() req: AuthenticatedRequest, @Query() query: Record<string, unknown>) {
    if (useFakeProvider()) return this.demo.grades(query);
    return this.edupage.gradesList(req.authClaims, query);
  }
  @UseGuards(AccessTokenGuard)
  @Get("essen") meals() { return this.demo.meals(); }
  @UseGuards(AccessTokenGuard)
  @Get("wetter") weather(@Query() query: Record<string, unknown>) { return this.demo.weather(query); }
  @UseGuards(AccessTokenGuard)
  @Get("wetter/suche") searchCities(@Query("q") query: unknown) { return this.demo.searchCities(query); }
  @UseGuards(AccessTokenGuard)
  @Get("settings") settings(@Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.settings(req.authClaims);
    return this.edupage.settingsGet(req.authClaims);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Put("settings") saveSettings(@Req() req: AuthenticatedRequest, @Body() body: unknown) {
    if (useFakeProvider()) return this.demo.saveSettings(req.authClaims, body);
    return this.edupage.settingsPut(req.authClaims, body);
  }
  @UseGuards(AccessTokenGuard)
  @HttpCode(HttpStatus.OK) @Post("cache-clear") clearCache(@Req() req: AuthenticatedRequest) {
    if (useFakeProvider()) return this.demo.clearCache(req.authClaims);
    return this.edupage.cacheClear(req.authClaims);
  }
}
