"use client";

// The PDF itself: jsPDF, loaded only when a PDF is made, fills the laid-out
// pages with the board pictures, a header and page numbers.
import { PAGE, type Page } from "../../../lib/tactics/pdf-layout.ts";

export type PdfInput = {
  projectName: string;
  subtitle: string | null;
  pages: Page[];
  /** The picture for a board's frame, keyed "board:frame". */
  pictures: Map<string, string>;
};

export async function buildPdf(input: PdfInput): Promise<Blob> {
  const { jsPDF } = await import("jspdf");
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4", compress: true });
  const date = new Date().toLocaleDateString("sv-SE", { day: "numeric", month: "long", year: "numeric" });
  input.pages.forEach((page, index) => {
    if (index > 0) doc.addPage();
    // Header: the project, then the board; the date to the right.
    doc.setTextColor(15, 23, 38);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(15);
    doc.text(input.projectName, PAGE.margin, PAGE.margin + 5);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(10);
    doc.setTextColor(91, 101, 119);
    doc.text([page.title, input.subtitle].filter(Boolean).join(" · "), PAGE.margin, PAGE.margin + 11);
    doc.text(date, PAGE.width - PAGE.margin, PAGE.margin + 5, { align: "right" });
    doc.setDrawColor(227, 231, 238);
    doc.line(PAGE.margin, PAGE.margin + 13.5, PAGE.width - PAGE.margin, PAGE.margin + 13.5);

    for (const item of page.placements) {
      const picture = input.pictures.get(`${item.boardIndex}:${item.frameIndex}`);
      if (picture) doc.addImage(picture, "JPEG", item.x, item.y, item.width, item.height, undefined, "FAST");
      let y = item.y + item.height + 4.5;
      if (item.caption) {
        doc.setFont("helvetica", "bold");
        doc.setFontSize(9);
        doc.setTextColor(15, 23, 38);
        doc.text(item.caption, item.x, y);
        y += 4;
      }
      if (item.note) {
        doc.setFont("helvetica", "normal");
        doc.setFontSize(9);
        doc.setTextColor(60, 70, 85);
        const lines = doc.splitTextToSize(item.note, item.width) as string[];
        doc.text(lines.slice(0, 2), item.x, y);
      }
    }

    // Footer.
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.setTextColor(148, 160, 178);
    doc.text("TeamZone Webtools · Tacticsboard", PAGE.margin, PAGE.height - PAGE.margin + 2);
    doc.text(`Sida ${index + 1} av ${input.pages.length}`, PAGE.width - PAGE.margin, PAGE.height - PAGE.margin + 2, { align: "right" });
  });
  return doc.output("blob");
}
