const ZIP_VERSION = 20;
const DOS_TIME = 0;
const DOS_DATE_1980_01_01 = 0x21;

interface ZipEntry {
  readonly name: string;
  readonly content: Uint8Array;
}

const UTF8_ENCODER = new TextEncoder();

function utf8(value: string): Uint8Array {
  return UTF8_ENCODER.encode(value);
}

function concatenate(parts: readonly Uint8Array[]): Uint8Array {
  const result = new Uint8Array(
    parts.reduce((length, part) => length + part.byteLength, 0),
  );
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.byteLength;
  }
  return result;
}

function writeUint16(target: Uint8Array, offset: number, value: number): void {
  new DataView(target.buffer, target.byteOffset, target.byteLength).setUint16(
    offset,
    value,
    true,
  );
}

function writeUint32(target: Uint8Array, offset: number, value: number): void {
  new DataView(target.buffer, target.byteOffset, target.byteLength).setUint32(
    offset,
    value,
    true,
  );
}

const CRC32_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < table.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) === 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
})();

function crc32(content: Uint8Array): number {
  let value = 0xffffffff;
  for (const byte of content) {
    value = CRC32_TABLE[(value ^ byte) & 0xff]! ^ (value >>> 8);
  }
  return (value ^ 0xffffffff) >>> 0;
}

function xmlText(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function xmlAttribute(value: string): string {
  return xmlText(value).replaceAll('"', "&quot;").replaceAll("'", "&apos;");
}

function columnReference(index: number): string {
  let value = index + 1;
  let result = "";
  while (value > 0) {
    value -= 1;
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = Math.floor(value / 26);
  }
  return result;
}

function sanitizeWorksheetName(value: string): string {
  const sanitized = value
    .replace(/[\\/?*:[\]]/g, " ")
    .trim()
    .slice(0, 31);
  return sanitized.length > 0 ? sanitized : "Export";
}

function createWorksheetXml(rows: readonly (readonly string[])[]): string {
  const width = rows[0]?.length ?? 1;
  const height = Math.max(rows.length, 1);
  const dimension = `A1:${columnReference(width - 1)}${height}`;
  const xmlRows = rows
    .map((row, rowIndex) => {
      const cells = row
        .map((value, columnIndex) => {
          const reference = `${columnReference(columnIndex)}${rowIndex + 1}`;
          return `<c r="${reference}" t="inlineStr"><is><t xml:space="preserve">${xmlText(value)}</t></is></c>`;
        })
        .join("");
      return `<row r="${rowIndex + 1}">${cells}</row>`;
    })
    .join("");

  return [
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    `<dimension ref="${dimension}"/>`,
    `<sheetData>${xmlRows}</sheetData>`,
    `<autoFilter ref="${dimension}"/>`,
    "</worksheet>",
  ].join("");
}

function createZip(entries: readonly ZipEntry[]): Uint8Array {
  const localParts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  let localOffset = 0;

  for (const entry of entries) {
    const name = utf8(entry.name);
    const checksum = crc32(entry.content);
    const localHeader = new Uint8Array(30);
    writeUint32(localHeader, 0, 0x04034b50);
    writeUint16(localHeader, 4, ZIP_VERSION);
    writeUint16(localHeader, 6, 0);
    writeUint16(localHeader, 8, 0);
    writeUint16(localHeader, 10, DOS_TIME);
    writeUint16(localHeader, 12, DOS_DATE_1980_01_01);
    writeUint32(localHeader, 14, checksum);
    writeUint32(localHeader, 18, entry.content.length);
    writeUint32(localHeader, 22, entry.content.length);
    writeUint16(localHeader, 26, name.length);
    writeUint16(localHeader, 28, 0);
    localParts.push(localHeader, name, entry.content);

    const centralHeader = new Uint8Array(46);
    writeUint32(centralHeader, 0, 0x02014b50);
    writeUint16(centralHeader, 4, ZIP_VERSION);
    writeUint16(centralHeader, 6, ZIP_VERSION);
    writeUint16(centralHeader, 8, 0);
    writeUint16(centralHeader, 10, 0);
    writeUint16(centralHeader, 12, DOS_TIME);
    writeUint16(centralHeader, 14, DOS_DATE_1980_01_01);
    writeUint32(centralHeader, 16, checksum);
    writeUint32(centralHeader, 20, entry.content.length);
    writeUint32(centralHeader, 24, entry.content.length);
    writeUint16(centralHeader, 28, name.length);
    writeUint16(centralHeader, 30, 0);
    writeUint16(centralHeader, 32, 0);
    writeUint16(centralHeader, 34, 0);
    writeUint16(centralHeader, 36, 0);
    writeUint32(centralHeader, 38, 0);
    writeUint32(centralHeader, 42, localOffset);
    centralParts.push(centralHeader, name);

    localOffset += localHeader.length + name.length + entry.content.length;
  }

  const centralDirectory = concatenate(centralParts);
  const end = new Uint8Array(22);
  writeUint32(end, 0, 0x06054b50);
  writeUint16(end, 4, 0);
  writeUint16(end, 6, 0);
  writeUint16(end, 8, entries.length);
  writeUint16(end, 10, entries.length);
  writeUint32(end, 12, centralDirectory.length);
  writeUint32(end, 16, localOffset);
  writeUint16(end, 20, 0);

  return concatenate([...localParts, centralDirectory, end]);
}

export function createDeterministicXlsx(
  worksheetName: string,
  rows: readonly (readonly string[])[],
): Uint8Array {
  const sheetName = sanitizeWorksheetName(worksheetName);
  const entries: ZipEntry[] = [
    {
      name: "[Content_Types].xml",
      content: utf8(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
          '<Default Extension="xml" ContentType="application/xml"/>' +
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
          "</Types>",
      ),
    },
    {
      name: "_rels/.rels",
      content: utf8(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
          "</Relationships>",
      ),
    },
    {
      name: "xl/workbook.xml",
      content: utf8(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
          `<sheets><sheet name="${xmlAttribute(sheetName)}" sheetId="1" r:id="rId1"/></sheets>` +
          "</workbook>",
      ),
    },
    {
      name: "xl/_rels/workbook.xml.rels",
      content: utf8(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
          "</Relationships>",
      ),
    },
    {
      name: "xl/worksheets/sheet1.xml",
      content: utf8(createWorksheetXml(rows)),
    },
  ];

  return createZip(entries);
}
