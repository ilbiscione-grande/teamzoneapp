import { Barlow_Condensed, Inter } from "next/font/google";
import "./globals.css";
import { AccountProvider } from "../components/account";
import { Footer, Header } from "../components/shell";

const display = Barlow_Condensed({ subsets: ["latin"], weight: ["600", "700", "800"], variable: "--wt-display", display: "swap" });
const body = Inter({ subsets: ["latin"], variable: "--wt-body", display: "swap" });

export const metadata = {
  title: { default: "TeamZone Webtools", template: "%s | TeamZone Webtools" },
  description: "Verktyg för lag och klubbar: taktiktavla, videoanalys, bokningar och turneringar, med ditt TeamZone-konto.",
  // A temporary address until webtools.teamzoneapp.se moves over.
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="sv" className={`${display.variable} ${body.variable}`}>
      <body>
        <AccountProvider>
          <div className="wt-shell">
            <Header />
            <main className="wt-main">{children}</main>
            <Footer />
          </div>
        </AccountProvider>
      </body>
    </html>
  );
}
