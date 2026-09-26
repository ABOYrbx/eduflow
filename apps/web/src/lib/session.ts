import { cookies } from "next/headers";

export async function currentUsername(): Promise<string | null> {
  const token = (await cookies()).get("eduflow_access")?.value;
  if (!token) return null;
  const response = await fetch(`${process.env.API_SERVER_URL ?? "http://127.0.0.1:8001"}/api/v1/me`, { headers: { authorization: `Bearer ${token}` }, cache: "no-store" }).catch(() => null);
  if (!response?.ok) return null;
  const profile = await response.json().catch(() => null) as { username?: unknown } | null;
  return typeof profile?.username === "string" ? profile.username : null;
}
