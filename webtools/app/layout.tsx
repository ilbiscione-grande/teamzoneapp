import { Barlow_Condensed, Inter } from "next/font/google";
import "./globals.css";
import { AccountProvider } from "../components/account";
import { LanguageProvider } from "../components/language";
import { Footer, Header } from "../components/shell";
import { englishOpen, serverLocale, serverT } from "../lib/i18n/server";

const display = Barlow_Condensed({ subsets: ["latin"], weight: ["600", "700", "800"], variable: "--wt-display", display: "swap" });
const body = Inter({ subsets: ["latin"], variable: "--wt-body", display: "swap" });

export async function generateMetadata() {
  const t = await serverT();
  return {
    title: { default: "TeamZone Webtools", template: "%s | TeamZone Webtools" },
    description: t("Verktyg för lag och klubbar: taktiktavla, videoanalys, bokningar och turneringar, med ditt TeamZone-konto."),
    // A temporary address until webtools.teamzoneapp.se moves over.
    robots: { index: false, follow: false },
  };
}

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const locale = await serverLocale();
  return (
    <html lang={locale} className={`${display.variable} ${body.variable}`}>
      <body>
        <LanguageProvider locale={locale} switchable={englishOpen()}>
          <AccountProvider>
            <div className="wt-shell">
              <Header />
              <main className="wt-main">{children}</main>
              <Footer />
            </div>
          </AccountProvider>
        </LanguageProvider>
      </body>
    </html>
  );
}
