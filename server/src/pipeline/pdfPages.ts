import { PDFDocument } from 'pdf-lib';

/**
 * Builds a new, smaller PDF containing only the given 1-indexed pages, in the order given
 * (duplicates dropped) — used when a member selects specific pages out of a large multi-page
 * PDF instead of uploading (and paying to have a model read through) the whole thing. Out-of-
 * range page numbers are ignored rather than throwing, since the client's own page count check
 * could in principle be stale relative to the actual file received.
 */
export async function extractPdfPages(buffer: Buffer, pageNumbers: number[]): Promise<Buffer> {
  const src = await PDFDocument.load(buffer);
  const totalPages = src.getPageCount();
  const zeroIndexed = [...new Set(pageNumbers)].filter((n) => n >= 1 && n <= totalPages).map((n) => n - 1);

  if (zeroIndexed.length === 0) return buffer; // nothing valid selected — fall back to the whole file

  const out = await PDFDocument.create();
  const copied = await out.copyPages(src, zeroIndexed);
  for (const page of copied) out.addPage(page);
  return Buffer.from(await out.save());
}
