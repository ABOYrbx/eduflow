import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { EdupageDataService } from "../edupage/data";

/**
 * Polls EduPage for every stored account once per minute.
 *
 * The poll refreshes the timeline cache and pulls new message attachments
 * onto the server, so clients can download them from the API without
 * contacting EduPage themselves. Disable with EDUFLOW_POLL_ENABLED=false;
 * the interval defaults to 60 s (EDUFLOW_POLL_INTERVAL_MS).
 */
@Injectable()
export class MessageSyncService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MessageSyncService.name);
  private timer: NodeJS.Timeout | undefined;
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly edupage: EdupageDataService,
  ) {}

  onModuleInit(): void {
    if (process.env.EDUFLOW_PROVIDER === "fake") return;
    if ((process.env.EDUFLOW_POLL_ENABLED ?? "true").toLowerCase() === "false") return;
    const configured = Number.parseInt(process.env.EDUFLOW_POLL_INTERVAL_MS ?? "", 10);
    const interval = Number.isFinite(configured) && configured >= 10_000 ? configured : 60_000;
    this.timer = setInterval(() => void this.tick(), interval);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  private async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const accounts = await this.prisma.credentialVault.findMany({ select: { accountId: true } });
      let synced = 0;
      let attachments = 0;
      for (const account of accounts) {
        try {
          const result = await this.edupage.syncAccount(account.accountId);
          synced += 1;
          attachments += result.attachments;
        } catch (error) {
          const detail = error instanceof Error ? error.message : String(error);
          this.logger.warn(`Message poll failed for one account: ${detail}`);
        }
      }
      if (synced > 0) {
        this.logger.log(`Message poll refreshed ${synced} account(s), cached ${attachments} attachment(s)`);
      }
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      this.logger.warn(`Message poll skipped: ${detail}`);
    } finally {
      this.running = false;
    }
  }
}
