import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { clearAttachmentCache, readCachedAttachment, writeCachedAttachment } from "./attachment-cache";

describe("attachment cache", () => {
  const oldDir = process.env.EDUFLOW_ATTACHMENT_DIR;
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "eduflow-attachments-"));
    process.env.EDUFLOW_ATTACHMENT_DIR = dir;
  });

  afterEach(async () => {
    if (oldDir === undefined) delete process.env.EDUFLOW_ATTACHMENT_DIR;
    else process.env.EDUFLOW_ATTACHMENT_DIR = oldDir;
    await rm(dir, { recursive: true, force: true });
  });

  it("stores and returns a downloaded file", async () => {
    await writeCachedAttachment("acc-1", 4101, 0, {
      filename: "plan.pdf",
      contentType: "application/pdf",
      bytes: Buffer.from("hello"),
    });
    const got = await readCachedAttachment("acc-1", 4101, 0);
    expect(got).not.toBeNull();
    expect(got?.filename).toBe("plan.pdf");
    expect(got?.contentType).toBe("application/pdf");
    expect(got?.bytes.toString()).toBe("hello");
  });

  it("isolates attachments by account, message and index", async () => {
    await writeCachedAttachment("acc-1", 4101, 0, {
      filename: "a.txt", contentType: "text/plain", bytes: Buffer.from("a"),
    });
    expect(await readCachedAttachment("acc-2", 4101, 0)).toBeNull();
    expect(await readCachedAttachment("acc-1", 4102, 0)).toBeNull();
    expect(await readCachedAttachment("acc-1", 4101, 1)).toBeNull();
  });

  it("clears one account without touching another", async () => {
    await writeCachedAttachment("acc-1", 1, 0, { filename: "a", contentType: "text/plain", bytes: Buffer.from("a") });
    await writeCachedAttachment("acc-2", 1, 0, { filename: "b", contentType: "text/plain", bytes: Buffer.from("b") });
    await clearAttachmentCache("acc-1");
    expect(await readCachedAttachment("acc-1", 1, 0)).toBeNull();
    expect(await readCachedAttachment("acc-2", 1, 0)).not.toBeNull();
  });
});
