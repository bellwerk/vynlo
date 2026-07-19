import { sha256Hex } from "./domain-common";

const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/u;
const UNSAFE_FILENAME_RUN = /[^A-Za-z0-9._-]+/gu;
const EDGE_PUNCTUATION = /^[.-]+|[.-]+$/gu;
const WINDOWS_RESERVED_STEM = /^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])$/iu;

/**
 * Preserve the legal number verbatim in the document while deriving a
 * deterministic, portable download filename. Unsafe or reserved names receive
 * a checksum suffix so distinct legal numbers cannot collapse to one filename.
 */
export function officialDocumentPdfFilename(officialNumber: string): string {
  const legalCharacterCount =
    typeof officialNumber === "string" ? Array.from(officialNumber).length : 0;
  if (
    typeof officialNumber !== "string" ||
    legalCharacterCount < 1 ||
    legalCharacterCount > 128 ||
    officialNumber.startsWith(" ") ||
    officialNumber.endsWith(" ") ||
    CONTROL_CHARACTER.test(officialNumber)
  ) {
    throw new TypeError("Invalid official document number.");
  }

  let portableStem = officialNumber
    .replaceAll(UNSAFE_FILENAME_RUN, "-")
    .replaceAll(EDGE_PUNCTUATION, "");
  if (portableStem.length === 0) portableStem = "document";
  const firstSegment = portableStem.split(".", 1)[0] ?? "";
  const requiresChecksum =
    portableStem !== officialNumber ||
    WINDOWS_RESERVED_STEM.test(firstSegment) ||
    officialNumber === "." ||
    officialNumber === "..";
  if (requiresChecksum) {
    portableStem = `${portableStem.slice(0, 100)}-${sha256Hex(officialNumber).slice(0, 16)}`;
  }
  return `${portableStem}.pdf`;
}
