import { NextRequest, NextResponse } from "next/server";
import "../../../lib/locales";
import { getCatalog, resolveLocale, supportedLocales } from "../../../lib/i18n";

/** Katalog einer Sprache für sofortigen clientseitigen Wechsel (kein Reload nötig). */
export async function GET(request: NextRequest) {
  const wanted = request.nextUrl.searchParams.get("lang");
  const locale = resolveLocale([wanted]);
  return NextResponse.json({ locale, catalog: getCatalog(locale), supported: supportedLocales() });
}
