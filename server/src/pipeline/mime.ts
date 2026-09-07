import path from 'node:path';

/** The only media types Claude's vision/document API accepts. */
export const SUPPORTED_MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf']);

const EXT_MAP: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.pdf': 'application/pdf',
};

/**
 * Multer trusts whatever Content-Type a client declares per-file, and not every client sets one
 * correctly (a generic multipart client can default to application/octet-stream). Since Claude's
 * API rejects anything outside SUPPORTED_MEDIA_TYPES, fall back to sniffing the file extension
 * whenever the declared type is missing or unsupported, rather than sending a doomed request.
 */
export function resolveMimeType(declaredMimeType: string | undefined, filename: string): string {
  const declared = declaredMimeType?.toLowerCase();
  if (declared && SUPPORTED_MEDIA_TYPES.has(declared)) return declared;
  const byExt = EXT_MAP[path.extname(filename).toLowerCase()];
  return byExt ?? declared ?? 'application/octet-stream';
}
