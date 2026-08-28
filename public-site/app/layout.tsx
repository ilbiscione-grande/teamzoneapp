import "./globals.css";

export const metadata = {
  metadataBase: new URL(process.env.PUBLIC_ORIGIN ?? "https://teamzoneapp.se"),
  title: { default: "TeamZone", template: "%s | TeamZone" },
  description: "Klubbar, lag och gemenskap i TeamZone.",
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="sv"><body><div className="site-shell">{children}</div></body></html>;
}
