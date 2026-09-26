import type { Metadata } from "next";
import Script from "next/script";
import { t } from "../lib/i18n";
import "./uber.css";
import "./compat.css";

export async function generateMetadata(): Promise<Metadata> {
  return { title: "EduFlow", description: t("meta.description") };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="de" suppressHydrationWarning>
    <head>
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
      <script dangerouslySetInnerHTML={{ __html: 'try{var t=localStorage.getItem("theme");if(!t&&window.matchMedia("(prefers-color-scheme: dark)").matches)t="dark";if(t)document.documentElement.dataset.theme=t;var a=localStorage.getItem("accent");if(a)document.documentElement.dataset.accent=a;}catch(e){}' }} />
    </head>
    <body>
      <Script src="/theme.js" strategy="beforeInteractive" />
      <Script src="/profile-menu.js" strategy="afterInteractive" />
      {children}
    </body>
  </html>;
}
