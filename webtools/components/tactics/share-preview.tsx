// A shared link's look in a chat: its title and description, and a picture
// of the board drawn on the server (lib/tactics/preview.ts), so the one who
// gets the link sees what it is before opening it.
import type { Metadata } from "next";
import { ImageResponse } from "next/og";
import { headers } from "next/headers";
import { kindNames, previewOf, previewSummary } from "../../lib/tactics/preview.ts";
import type { SharedTactics } from "../../lib/tactics/shared.ts";

export const PREVIEW_SIZE = { width: 1200, height: 630 };
const ACCENT = "#c6f04d";

/** Absolute addresses for the picture: the address the page was asked for (the domain will move). */
async function base(): Promise<URL | undefined> {
  const asked = await headers();
  const host = asked.get("x-forwarded-host") ?? asked.get("host");
  if (!host) return undefined;
  const local = host.startsWith("localhost") || host.startsWith("127.0.0.1");
  return new URL(`${local ? "http" : "https"}://${host}`);
}

/** The page's title and the text and picture a chat shows for the link. */
export async function sharedMetadata(shared: SharedTactics | null, fallback = "Delad tavla"): Promise<Metadata> {
  if (!shared) return { title: fallback };
  const summary = previewSummary(kindNames[shared.kind], shared.boards.length, shared.team_name);
  const description = `${summary}. Titta och spela upp i mobilen, inget konto behövs.`;
  return {
    metadataBase: await base(),
    title: shared.name,
    description,
    openGraph: { title: shared.name, description, siteName: "TeamZone Tacticsboard", type: "website" },
    twitter: { card: "summary_large_image", title: shared.name, description },
  };
}

/** The picture: the first board's first frame, the name and what it is. */
export function previewImage(shared: SharedTactics | null): ImageResponse {
  const board = shared?.boards[0];
  const preview = board ? previewOf(board) : null;
  // The pitch as large as fits above the text.
  const room = { width: 1104, height: 420 };
  const pitch = preview
    ? (preview.aspect > room.width / room.height ? { width: room.width, height: room.width / preview.aspect } : { width: room.height * preview.aspect, height: room.height })
    : null;
  const dot = 30;
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", alignItems: "center", background: "linear-gradient(#0b1424, #13221a)", padding: 48, paddingBottom: 36 }}>
        <div style={{ display: "flex", flex: 1, alignItems: "center", justifyContent: "center", width: "100%" }}>
          {preview && pitch && (
            <div style={{ position: "relative", display: "flex", width: pitch.width, height: pitch.height, background: "#2f7d46", borderRadius: 10 }}>
              {preview.lines.map((line, index) => (
                <div key={index} style={{
                  position: "absolute", left: line.left * pitch.width, top: line.top * pitch.height,
                  width: Math.max(3, line.width * pitch.width), height: line.height * pitch.height,
                  border: line.width === 0 ? "none" : "3px solid rgba(255,255,255,0.85)", borderRadius: line.round ? "50%" : 0,
                  background: line.width === 0 ? "rgba(255,255,255,0.85)" : "transparent",
                }} />
              ))}
              {preview.dots.map((item, index) => {
                const size = item.ball ? dot * 0.6 : dot;
                return (
                  <div key={`d${index}`} style={{
                    position: "absolute", left: item.left * pitch.width - size / 2, top: item.top * pitch.height - size / 2, width: size, height: size,
                    display: "flex", alignItems: "center", justifyContent: "center", borderRadius: "50%", background: item.fill,
                    border: `2px solid ${item.ball ? "#111827" : "#ffffff"}`, color: item.ink, fontSize: 15, fontWeight: 700,
                  }}>{item.label}</div>
                );
              })}
            </div>
          )}
        </div>
        <div style={{ display: "flex", width: "100%", alignItems: "flex-end", justifyContent: "space-between", marginTop: 24 }}>
          <div style={{ display: "flex", flexDirection: "column", maxWidth: 820 }}>
            <div style={{ display: "flex", fontSize: 48, fontWeight: 700, color: "#ffffff", lineHeight: 1.1 }}>{shared?.name ?? "Delad tavla"}</div>
            {shared && <div style={{ display: "flex", fontSize: 26, color: "#a9b4c4", marginTop: 8 }}>{previewSummary(kindNames[shared.kind], shared.boards.length, shared.team_name)}</div>}
          </div>
          <div style={{ display: "flex", alignItems: "center", fontSize: 24, color: "#ffffff" }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "center", width: 44, height: 44, borderRadius: 10, background: ACCENT, color: "#0b1424", fontWeight: 800, marginRight: 12 }}>TZ</div>
            Tacticsboard
          </div>
        </div>
      </div>
    ),
    PREVIEW_SIZE,
  );
}

/** A shared folder's title and the text a chat shows for its link. */
export async function folderMetadata(folder: { name: string; projects: unknown[] } | null): Promise<Metadata> {
  if (!folder) return { title: "Delad mapp" };
  const count = folder.projects.length;
  const description = `Mapp med ${count === 1 ? "1 projekt" : `${count} projekt`} från TeamZone Tacticsboard. Titta och spela upp i mobilen, inget konto behövs.`;
  return {
    metadataBase: await base(),
    title: folder.name,
    description,
    openGraph: { title: folder.name, description, siteName: "TeamZone Tacticsboard", type: "website" },
  };
}
