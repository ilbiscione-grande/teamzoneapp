"use client";

// The PDF itself: jsPDF, loaded only when a PDF is made, fills the laid-out
// pages with the board pictures, a header and page numbers. A description
// too long for its column goes on over pages of its own after it.
import { PAGE, type Page } from "../../../lib/tactics/pdf-layout.ts";

const LINE = 4.6;
/** A page of the PDF: a laid-out page, or one going on with a description. */
type Sheet = { page: Page | null; title: string; description: string[]; lines: string[] };

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

  // Descriptions are split first, so overflow pages count in the page numbers.
  doc.setFont("helvetica", "normal");
  doc.setFontSize(10);
  // Going on over a page of its own, the text keeps a width that reads well.
  const fullWidth = 190;
  const fullLines = Math.floor((PAGE.height - PAGE.margin * 2 - PAGE.header - PAGE.footer - 8) / LINE);
  const sheets: Sheet[] = [];
  for (const page of input.pages) {
    const box = page.description;
    if (!box) { sheets.push({ page, title: page.title, description: [], lines: [] }); continue; }
    // Each line remembers its paragraph, so the rest keeps its line breaks.
    const lines = box.text.split("\n").flatMap((paragraph, index) =>
      (paragraph.trim() ? doc.splitTextToSize(paragraph, box.width) as string[] : [""]).map(text => ({ text, paragraph: index })));
    const room = Math.floor((box.height - 8) / LINE);
    sheets.push({ page, title: page.title, description: lines.slice(0, room).map(line => line.text), lines: [] });
    if (lines.length > room) {
      const paragraphs = lines.slice(room).reduce<string[]>((all, line, index, rest) => {
        if (index > 0 && rest[index - 1].paragraph === line.paragraph) all[all.length - 1] += " " + line.text;
        else all.push(line.text);
        return all;
      }, []);
      const rest = paragraphs.flatMap(paragraph => paragraph.trim() ? doc.splitTextToSize(paragraph, fullWidth) as string[] : [""]);
      for (let start = 0; start < rest.length; start += fullLines) {
        sheets.push({ page: null, title: page.title, description: [], lines: rest.slice(start, start + fullLines) });
      }
    }
  }

  sheets.forEach((sheet, index) => {
    if (index > 0) doc.addPage();
    const { page, title } = sheet;
    // Header: the project, then the board; the date to the right.
    doc.setTextColor(15, 23, 38);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(15);
    doc.text(input.projectName, PAGE.margin, PAGE.margin + 5);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(10);
    doc.setTextColor(91, 101, 119);
    doc.text([title, input.subtitle].filter(Boolean).join(" · "), PAGE.margin, PAGE.margin + 11);
    doc.text(date, PAGE.width - PAGE.margin, PAGE.margin + 5, { align: "right" });
    doc.setDrawColor(227, 231, 238);
    doc.line(PAGE.margin, PAGE.margin + 13.5, PAGE.width - PAGE.margin, PAGE.margin + 13.5);

    const top = PAGE.margin + PAGE.header;
    if (!page) {
      doc.setFont("helvetica", "bold");
      doc.setFontSize(10);
      doc.setTextColor(15, 23, 38);
      doc.text("Beskrivning (forts.)", PAGE.margin, top + 4);
      doc.setFont("helvetica", "normal");
      doc.setTextColor(40, 48, 62);
      doc.text(sheet.lines, PAGE.margin, top + 4 + 6, { lineHeightFactor: LINE / (10 * 0.3528) });
    }
    if (page?.description) {
      const box = page.description;
      doc.setFillColor(247, 249, 251);
      doc.roundedRect(box.x - 3, box.y - 2, box.width + 6, Math.min(box.height + 2, sheet.description.length * LINE + 14), 2, 2, "F");
      doc.setFont("helvetica", "bold");
      doc.setFontSize(10);
      doc.setTextColor(15, 23, 38);
      doc.text("Beskrivning", box.x, box.y + 4);
      doc.setFont("helvetica", "normal");
      doc.setTextColor(40, 48, 62);
      doc.text(sheet.description, box.x, box.y + 10, { lineHeightFactor: LINE / (10 * 0.3528) });
    }

    for (const item of page?.placements ?? []) {
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
    doc.text(`Sida ${index + 1} av ${sheets.length}`, PAGE.width - PAGE.margin, PAGE.height - PAGE.margin + 2, { align: "right" });
  });
  return doc.output("blob");
}
