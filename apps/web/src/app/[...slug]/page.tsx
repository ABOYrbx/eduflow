import { notFound, redirect } from "next/navigation";
import { DashboardApp } from "@/components/dashboard-app";
import { currentUsername } from "@/lib/session";

const supported = new Set(["messages", "homework", "grades", "timetable", "agenda", "settings", "sessions", "mehr"]);

export default async function SectionPage({ params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  if (slug.length !== 1 || !supported.has(slug[0] ?? "")) notFound();
  const username = await currentUsername();
  if (!username) redirect("/login");
  return <DashboardApp username={username} />;
}
