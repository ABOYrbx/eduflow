import { redirect } from "next/navigation";
import { DashboardApp } from "@/components/dashboard-app";
import { currentUsername } from "@/lib/session";

export default async function HomePage() {
  const username = await currentUsername();
  if (username) return <DashboardApp username={username} />;
  redirect("/login");
}
