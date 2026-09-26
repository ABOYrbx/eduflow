import { NextRequest, NextResponse } from "next/server";

export async function POST(request: NextRequest) {
  const token = request.cookies.get("eduflow_access")?.value;
  if (token) {
    await fetch(`${process.env.API_SERVER_URL ?? "http://127.0.0.1:8000"}/api/v1/auth/logout`, {
      method: "POST", headers: { authorization: `Bearer ${token}` },
    }).catch(() => null);
  }
  const response = NextResponse.json({ status: "ok" });
  response.cookies.delete("eduflow_access"); response.cookies.delete("eduflow_refresh"); response.cookies.delete("eduflow_pending");
  return response;
}
