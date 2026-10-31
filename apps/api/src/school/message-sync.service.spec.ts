import { MessageSyncService } from "./message-sync.service";

describe("MessageSyncService", () => {
  it("polls every stored account and keeps going after one failure", async () => {
    const prisma = {
      credentialVault: {
        findMany: jest.fn(async () => [{ accountId: "a" }, { accountId: "b" }]),
      },
    };
    const edupage = {
      syncAccount: jest.fn(async (accountId: string) => {
        if (accountId === "b") throw new Error("upstream down");
        return { messages: 3, attachments: 1 };
      }),
    };
    const service = new MessageSyncService(prisma as never, edupage as never);
    await (service as unknown as { tick: () => Promise<void> }).tick();
    expect(edupage.syncAccount).toHaveBeenCalledTimes(2);
    expect(edupage.syncAccount).toHaveBeenCalledWith("a");
    expect(edupage.syncAccount).toHaveBeenCalledWith("b");
  });

  it("ignores a second tick while the first is still running", async () => {
    let release: (() => void) | undefined;
    const prisma = {
      credentialVault: {
        findMany: jest.fn(async () => [{ accountId: "a" }]),
      },
    };
    const edupage = {
      syncAccount: jest.fn(() => new Promise((resolve) => { release = () => resolve({ messages: 0, attachments: 0 }); })),
    };
    const service = new MessageSyncService(prisma as never, edupage as never);
    const run = service as unknown as { tick: () => Promise<void> };
    const first = run.tick();
    await run.tick();
    expect(edupage.syncAccount).toHaveBeenCalledTimes(1);
    release?.();
    await first;
  });
});
