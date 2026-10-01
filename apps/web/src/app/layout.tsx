import type { Metadata } from "next";
import Script from "next/script";
import { LocaleProvider } from "../components/locale-provider";
import { getCatalog, supportedLocales, t } from "../lib/i18n";
import { requestLocale } from "../lib/request-locale";
import { languageCoverage } from "../lib/i18n";
import "./uber.css";
import "./compat.css";

export async function generateMetadata(): Promise<Metadata> {
  const locale = await requestLocale();
  return { title: "EduFlow", description: t("meta.description", undefined, locale) };
}

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const locale = await requestLocale();
  const payload = JSON.stringify({
    locale,
    catalog: getCatalog(locale),
    supported: supportedLocales(),
    coverage: languageCoverage(),
  }).replace(/</g, "\\u003c");
  return <html lang={locale} suppressHydrationWarning>
    <head>
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
      <script dangerouslySetInnerHTML={{ __html: `window.__EDUFLOW_MESSAGES__=${payload};` }} />
      <script dangerouslySetInnerHTML={{ __html: 'try{var t=localStorage.getItem("theme");if(!t&&window.matchMedia("(prefers-color-scheme: dark)").matches)t="dark";if(t)document.documentElement.dataset.theme=t;var a=localStorage.getItem("accent");if(a)document.documentElement.dataset.accent=a;}catch(e){}' }} />
    </head>
    <body>
      <Script src="/theme.js" strategy="beforeInteractive" />
      <Script src="/profile-menu.js" strategy="afterInteractive" />
      <LocaleProvider>{children}</LocaleProvider>
    </body>
  </html>;
}
