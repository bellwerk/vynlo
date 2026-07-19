import {
  assertExactKeys,
  canonicalJson,
  DocumentDomainError,
  normalizeIsoInstant,
  requireBoundedText,
  requireChecksum,
  requireDenseArray,
  requireKey,
  requirePlainRecord,
  sha256Hex,
  type PlainRecord,
} from "./domain-common";

export const DOCUMENT_TEMPLATE_LIMITS = Object.freeze({
  maximumAssets: 64,
  maximumAssetBytes: 10_000_000,
  maximumCombinedAssetBytes: 25_000_000,
  maximumLoopDepth: 4,
  maximumLoopItems: 1_000,
  maximumNodes: 5_000,
  maximumOutputBytes: 5_000_000,
  maximumRenderIterations: 10_000,
  maximumSourceBytes: 1_000_000,
  maximumSyntaxDepth: 16,
});

const TEMPLATE_PATH_PATTERN =
  /^[a-zA-Z_][a-zA-Z0-9_]{0,63}(?:\.(?:[a-zA-Z_][a-zA-Z0-9_]{0,63}|\d{1,4}))*$/u;
const LOOP_VARIABLE_PATTERN = /^[a-z][a-z0-9_]{0,63}$/u;
const PROHIBITED_PATH_SEGMENTS = new Set([
  "__proto__",
  "constructor",
  "prototype",
]);
const ASSET_MIME_TYPES = new Set([
  "font/woff",
  "font/woff2",
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const UNSAFE_MARKUP = [
  /<\s*(?:script|style|iframe|object|embed|base|form|link)\b/iu,
  /<\s*meta\b[^>]*http-equiv\s*=/iu,
  /\bon[a-z]+\s*=/iu,
  /\bsrcdoc\s*=/iu,
  /\bstyle\s*=/iu,
  /(?:java|vb)script\s*:/iu,
  /\bexpression\s*\(/iu,
  /\bimage-set\s*\(/iu,
  /\blocal\s*\(/iu,
  /@import\b/iu,
  /<!--\s*\[if/iu,
];
const ATTRIBUTE_RESOURCE_PATTERN =
  /\b(src|href|action|formaction|poster|background|manifest|ping|srcset)\s*=\s*(?:(["'])(.*?)\2|([^\s>]+))/giu;
const CSS_RESOURCE_PATTERN = /url\s*\(\s*(?:(["'])(.*?)\1|([^\s)]+))\s*\)/giu;
const ASSET_REFERENCE_PATTERN = /^vynlo-asset:([a-z][a-z0-9_.-]{0,127})$/u;
const MONEY_MINOR_PATTERN = /^(?:0|-?[1-9][0-9]{0,18})$/u;
const POSTGRES_BIGINT_MIN = -9_223_372_036_854_775_808n;
const POSTGRES_BIGINT_MAX = 9_223_372_036_854_775_807n;

export interface DocumentTemplateAsset {
  readonly key: string;
  readonly filename: string;
  readonly mimeType: string;
  readonly byteSize: number;
  readonly checksum: string;
  /** Canonical lower-case hexadecimal bytes; immutable and idempotently validated. */
  readonly content: string;
}

export interface DocumentTemplateSourceBundle {
  readonly sourceHtml: string;
  readonly sourceCss: string;
  readonly assets: readonly DocumentTemplateAsset[];
  readonly checksum: string;
}

interface TextNode {
  readonly type: "text";
  readonly value: string;
}

interface FilterNode {
  readonly name: "default" | "date" | "money";
  readonly arguments: readonly (string | number)[];
}

interface OutputNode {
  readonly type: "output";
  readonly path: string;
  readonly filters: readonly FilterNode[];
}

type ConditionLiteral = string | number | boolean | null;

interface ConditionNode {
  readonly path: string;
  readonly negate: boolean;
  readonly operator: "truthy" | "equal" | "not_equal";
  readonly literal: ConditionLiteral;
}

interface IfNode {
  readonly type: "if";
  readonly condition: ConditionNode;
  readonly consequent: readonly TemplateNode[];
  readonly alternate: readonly TemplateNode[];
}

interface ForNode {
  readonly type: "for";
  readonly variable: string;
  readonly collectionPath: string;
  readonly body: readonly TemplateNode[];
}

type TemplateNode = TextNode | OutputNode | IfNode | ForNode;

export interface CompiledDocumentTemplate {
  readonly sourceChecksum: string;
  readonly sourceBundle: DocumentTemplateSourceBundle;
  readonly assetKeys: readonly string[];
  readonly nodeCount: number;
  /** Opaque immutable AST. Callers render through renderDocumentTemplate. */
  readonly nodes: readonly TemplateNode[];
}

const COMPILED_TEMPLATES = new WeakSet<object>();

interface Token {
  readonly type: "text" | "output" | "tag";
  readonly value: string;
}

function bytesOf(value: unknown): Uint8Array {
  if (value instanceof Uint8Array) {
    return new Uint8Array(value);
  }
  if (
    typeof value !== "string" ||
    value.length < 2 ||
    value.length > DOCUMENT_TEMPLATE_LIMITS.maximumAssetBytes * 2 ||
    value.length % 2 !== 0 ||
    !/^[a-f0-9]+$/u.test(value)
  ) {
    throw new DocumentDomainError("invalid_definition", "asset_content");
  }
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function bytesToHex(value: Uint8Array): string {
  const chunks: string[] = [];
  for (let offset = 0; offset < value.length; offset += 4_096) {
    let chunk = "";
    const end = Math.min(offset + 4_096, value.length);
    for (let index = offset; index < end; index += 1) {
      chunk += (value[index] ?? 0).toString(16).padStart(2, "0");
    }
    chunks.push(chunk);
  }
  return chunks.join("");
}

function startsWithBytes(
  value: Uint8Array,
  expected: readonly number[],
): boolean {
  return expected.every((byte, index) => value[index] === byte);
}

function assertAssetSignature(mimeType: string, content: Uint8Array): void {
  const ascii = (offset: number, length: number) =>
    new TextDecoder("ascii").decode(content.slice(offset, offset + length));
  const valid =
    (mimeType === "image/png" &&
      startsWithBytes(
        content,
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      )) ||
    (mimeType === "image/jpeg" &&
      startsWithBytes(content, [0xff, 0xd8, 0xff])) ||
    (mimeType === "image/webp" &&
      ascii(0, 4) === "RIFF" &&
      ascii(8, 4) === "WEBP") ||
    (mimeType === "font/woff" && ascii(0, 4) === "wOFF") ||
    (mimeType === "font/woff2" && ascii(0, 4) === "wOF2");
  if (!valid) {
    throw new DocumentDomainError("unsafe_template_source", "asset_signature");
  }
}

function normalizeAsset(value: unknown): DocumentTemplateAsset {
  const record = requirePlainRecord(value);
  assertExactKeys(record, [
    "key",
    "filename",
    "mimeType",
    "byteSize",
    "checksum",
    "content",
  ]);
  const key = requireKey(record.key);
  const filename = requireBoundedText(record.filename, 255);
  if (
    filename.includes("/") ||
    filename.includes("\\") ||
    filename === "." ||
    filename === ".." ||
    /[\u0000-\u001f\u007f]/u.test(filename)
  ) {
    throw new DocumentDomainError("invalid_definition", "asset_filename");
  }
  const mimeType = requireBoundedText(record.mimeType, 100).toLowerCase();
  if (!ASSET_MIME_TYPES.has(mimeType)) {
    throw new DocumentDomainError("unsafe_template_source", "asset_mime_type");
  }
  const content = bytesOf(record.content);
  if (
    !Number.isSafeInteger(record.byteSize) ||
    (record.byteSize as number) < 1 ||
    (record.byteSize as number) > DOCUMENT_TEMPLATE_LIMITS.maximumAssetBytes ||
    record.byteSize !== content.byteLength
  ) {
    throw new DocumentDomainError("invalid_definition", "asset_byte_size");
  }
  const checksum = requireChecksum(record.checksum);
  assertAssetSignature(mimeType, content);
  if (sha256Hex(content) !== checksum) {
    throw new DocumentDomainError("checksum_mismatch", key);
  }
  return Object.freeze({
    key,
    filename,
    mimeType,
    byteSize: content.byteLength,
    checksum,
    content: bytesToHex(content),
  });
}

function bundleChecksumPayload(input: {
  readonly sourceHtml: string;
  readonly sourceCss: string;
  readonly assets: readonly Pick<
    DocumentTemplateAsset,
    "key" | "filename" | "mimeType" | "byteSize" | "checksum"
  >[];
}): unknown {
  return {
    sourceHtml: input.sourceHtml,
    sourceCss: input.sourceCss,
    assets: [...input.assets]
      .sort((left, right) => left.key.localeCompare(right.key, "en"))
      .map(({ key, filename, mimeType, byteSize, checksum }) => ({
        key,
        filename,
        mimeType,
        byteSize,
        checksum,
      })),
  };
}

export function computeTemplateSourceBundleChecksum(input: {
  readonly sourceHtml: string;
  readonly sourceCss: string;
  readonly assets: readonly Pick<
    DocumentTemplateAsset,
    "key" | "filename" | "mimeType" | "byteSize" | "checksum"
  >[];
}): string {
  return sha256Hex(canonicalJson(bundleChecksumPayload(input)));
}

export function normalizeTemplateSourceBundle(
  value: unknown,
): DocumentTemplateSourceBundle {
  const record = requirePlainRecord(value);
  assertExactKeys(record, ["sourceHtml", "sourceCss", "assets", "checksum"]);
  if (
    typeof record.sourceHtml !== "string" ||
    typeof record.sourceCss !== "string"
  ) {
    throw new DocumentDomainError("invalid_definition", "template_source");
  }
  const sourceHtml = record.sourceHtml;
  const sourceCss = record.sourceCss;
  const sourceBytes = new TextEncoder().encode(
    sourceHtml + sourceCss,
  ).byteLength;
  if (
    !sourceHtml.trim() ||
    sourceBytes > DOCUMENT_TEMPLATE_LIMITS.maximumSourceBytes ||
    sourceHtml.includes("\u0000") ||
    sourceCss.includes("\u0000")
  ) {
    throw new DocumentDomainError("template_resource_limit", "source_bytes");
  }
  const assetValues = requireDenseArray(record.assets);
  if (assetValues.length > DOCUMENT_TEMPLATE_LIMITS.maximumAssets) {
    throw new DocumentDomainError("template_resource_limit", "asset_count");
  }
  const assets = assetValues
    .map(normalizeAsset)
    .sort((left, right) => left.key.localeCompare(right.key, "en"));
  if (new Set(assets.map((asset) => asset.key)).size !== assets.length) {
    throw new DocumentDomainError("invalid_definition", "duplicate_asset_key");
  }
  const combinedAssetBytes = assets.reduce(
    (sum, asset) => sum + asset.byteSize,
    0,
  );
  if (combinedAssetBytes > DOCUMENT_TEMPLATE_LIMITS.maximumCombinedAssetBytes) {
    throw new DocumentDomainError("template_resource_limit", "asset_bytes");
  }
  const checksum = requireChecksum(record.checksum);
  if (
    computeTemplateSourceBundleChecksum({ sourceHtml, sourceCss, assets }) !==
    checksum
  ) {
    throw new DocumentDomainError("checksum_mismatch", "source_bundle");
  }
  return Object.freeze({
    sourceHtml,
    sourceCss,
    assets: Object.freeze(assets),
    checksum,
  });
}

function assertPath(path: string): string {
  const normalized = path.trim();
  if (
    !TEMPLATE_PATH_PATTERN.test(normalized) ||
    normalized
      .split(".")
      .some((segment) => PROHIBITED_PATH_SEGMENTS.has(segment.toLowerCase()))
  ) {
    throw new DocumentDomainError("template_syntax_invalid", "path");
  }
  return normalized;
}

function resourceValue(value: string): {
  assetKey: string | null;
  safe: boolean;
} {
  const normalized = value.trim();
  const asset = ASSET_REFERENCE_PATTERN.exec(normalized);
  if (asset?.[1]) return { assetKey: asset[1], safe: true };
  if (normalized.startsWith("#")) return { assetKey: null, safe: true };
  return { assetKey: null, safe: false };
}

function assertTemplateSyntaxContexts(
  sourceHtml: string,
  sourceCss: string,
): void {
  if (sourceCss.includes("{{") || sourceCss.includes("{%")) {
    throw new DocumentDomainError("unsafe_template_source", "dynamic_css");
  }
  if (sourceCss.includes("\\")) {
    throw new DocumentDomainError("unsafe_template_source", "css_escape");
  }
  let insideMarkup = false;
  for (let index = 0; index < sourceHtml.length; index += 1) {
    const character = sourceHtml[index];
    if (character === "<") {
      insideMarkup = true;
    } else if (character === ">") {
      insideMarkup = false;
    } else if (
      insideMarkup &&
      character === "{" &&
      ["{", "%"].includes(sourceHtml[index + 1] ?? "")
    ) {
      throw new DocumentDomainError("unsafe_template_source", "dynamic_markup");
    }
  }
}

function assertSafeSource(
  sourceHtml: string,
  sourceCss: string,
): readonly string[] {
  assertTemplateSyntaxContexts(sourceHtml, sourceCss);
  const combined = `${sourceHtml}\n${sourceCss}`;
  for (const pattern of UNSAFE_MARKUP) {
    if (pattern.test(combined)) {
      throw new DocumentDomainError("unsafe_template_source", pattern.source);
    }
  }
  if (combined.includes("{#") || combined.includes("#}")) {
    throw new DocumentDomainError(
      "template_syntax_invalid",
      "comments_not_supported",
    );
  }
  const assetKeys = new Set<string>();
  for (const match of combined.matchAll(ATTRIBUTE_RESOURCE_PATTERN)) {
    const attribute = match[1]?.toLowerCase();
    const value = match[3] ?? match[4] ?? "";
    const resource = resourceValue(value);
    if (
      ["action", "formaction", "manifest", "ping", "srcset"].includes(
        attribute ?? "",
      ) ||
      !resource.safe ||
      (resource.assetKey === null && attribute !== "href")
    ) {
      throw new DocumentDomainError(
        "unsafe_template_source",
        attribute ?? "attribute",
      );
    }
    if (resource.assetKey) assetKeys.add(resource.assetKey);
  }
  for (const match of combined.matchAll(CSS_RESOURCE_PATTERN)) {
    const value = match[2] ?? match[3] ?? "";
    const resource = resourceValue(value);
    if (!resource.safe || resource.assetKey === null) {
      throw new DocumentDomainError("unsafe_template_source", "css_url");
    }
    assetKeys.add(resource.assetKey);
  }
  return Object.freeze([...assetKeys].sort());
}

function tokenize(source: string): readonly Token[] {
  const tokens: Token[] = [];
  let offset = 0;
  while (offset < source.length) {
    const outputIndex = source.indexOf("{{", offset);
    const tagIndex = source.indexOf("{%", offset);
    const candidates = [outputIndex, tagIndex].filter((index) => index >= 0);
    if (candidates.length === 0) {
      tokens.push({ type: "text", value: source.slice(offset) });
      break;
    }
    const next = Math.min(...candidates);
    if (next > offset)
      tokens.push({ type: "text", value: source.slice(offset, next) });
    const output = next === outputIndex;
    const close = output ? "}}" : "%}";
    const end = source.indexOf(close, next + 2);
    if (end < 0) {
      throw new DocumentDomainError("template_syntax_invalid", "unclosed_tag");
    }
    const value = source.slice(next + 2, end).trim();
    if (!value)
      throw new DocumentDomainError("template_syntax_invalid", "empty_tag");
    tokens.push({ type: output ? "output" : "tag", value });
    offset = end + 2;
    if (tokens.length > DOCUMENT_TEMPLATE_LIMITS.maximumNodes * 2) {
      throw new DocumentDomainError("template_resource_limit", "tokens");
    }
  }
  return tokens;
}

function splitOutsideQuotes(
  value: string,
  separator: string,
): readonly string[] {
  const result: string[] = [];
  let quote: string | null = null;
  let current = "";
  for (const character of value) {
    if ((character === '"' || character === "'") && quote === null) {
      quote = character;
    } else if (character === quote) {
      quote = null;
    } else if (character === separator && quote === null) {
      result.push(current.trim());
      current = "";
      continue;
    }
    current += character;
  }
  if (quote !== null)
    throw new DocumentDomainError("template_syntax_invalid", "quote");
  result.push(current.trim());
  return result;
}

function parseLiteral(value: string): ConditionLiteral {
  const normalized = value.trim();
  if (
    (normalized.startsWith('"') && normalized.endsWith('"')) ||
    (normalized.startsWith("'") && normalized.endsWith("'"))
  ) {
    const inner = normalized.slice(1, -1);
    if (inner.length > 500 || inner.includes(normalized[0] ?? "")) {
      throw new DocumentDomainError("template_syntax_invalid", "literal");
    }
    return inner;
  }
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  if (normalized === "null") return null;
  if (/^-?(?:0|[1-9]\d*)(?:\.\d+)?$/u.test(normalized)) {
    const parsed = Number(normalized);
    if (Number.isFinite(parsed)) return parsed;
  }
  throw new DocumentDomainError("template_syntax_invalid", "literal");
}

function parseFilter(value: string): FilterNode {
  const [namePart, ...argumentParts] = splitOutsideQuotes(value, ":");
  if (!namePart || argumentParts.length > 1) {
    throw new DocumentDomainError("template_syntax_invalid", "filter");
  }
  if (!["default", "date", "money"].includes(namePart)) {
    throw new DocumentDomainError("arbitrary_execution_not_allowed", namePart);
  }
  const argumentsValue = argumentParts[0];
  const args =
    argumentsValue === undefined
      ? []
      : splitOutsideQuotes(argumentsValue, ",").map(parseLiteral);
  if (namePart === "default") {
    if (args.length !== 1 || typeof args[0] !== "string") {
      throw new DocumentDomainError(
        "template_syntax_invalid",
        "default_filter",
      );
    }
  } else if (namePart === "date") {
    if (
      args.length !== 1 ||
      !["%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y"].includes(String(args[0]))
    ) {
      throw new DocumentDomainError("template_syntax_invalid", "date_filter");
    }
  } else if (
    args.length < 1 ||
    args.length > 2 ||
    typeof args[0] !== "string" ||
    !/^[A-Z]{3}$/u.test(args[0]) ||
    (args[1] !== undefined &&
      (!Number.isInteger(args[1]) ||
        (args[1] as number) < 0 ||
        (args[1] as number) > 6))
  ) {
    throw new DocumentDomainError("template_syntax_invalid", "money_filter");
  }
  return Object.freeze({
    name: namePart as FilterNode["name"],
    arguments: Object.freeze(args as (string | number)[]),
  });
}

function parseOutput(value: string): OutputNode {
  const [pathPart, ...filterParts] = splitOutsideQuotes(value, "|");
  if (
    !pathPart ||
    filterParts.length > 4 ||
    filterParts.some((part) => !part)
  ) {
    throw new DocumentDomainError("template_syntax_invalid", "output");
  }
  return Object.freeze({
    type: "output",
    path: assertPath(pathPart),
    filters: Object.freeze(filterParts.map(parseFilter)),
  });
}

function parseCondition(value: string): ConditionNode {
  let normalized = value.trim();
  let negate = false;
  if (normalized.startsWith("not ")) {
    negate = true;
    normalized = normalized.slice(4).trim();
  }
  const comparison = /^(.*?)\s*(==|!=)\s*(.*?)$/u.exec(normalized);
  if (!comparison) {
    return Object.freeze({
      path: assertPath(normalized),
      negate,
      operator: "truthy",
      literal: null,
    });
  }
  const path = comparison[1];
  const operator = comparison[2];
  const literal = comparison[3];
  if (!path || !operator || literal === undefined || negate) {
    throw new DocumentDomainError("template_syntax_invalid", "condition");
  }
  return Object.freeze({
    path: assertPath(path),
    negate: false,
    operator: operator === "==" ? "equal" : "not_equal",
    literal: parseLiteral(literal),
  });
}

function parseNodes(
  tokens: readonly Token[],
  state: { index: number; nodeCount: number },
  terminators: ReadonlySet<string>,
  depth: number,
  loopDepth: number,
): {
  readonly nodes: readonly TemplateNode[];
  readonly terminator: string | null;
} {
  if (depth > DOCUMENT_TEMPLATE_LIMITS.maximumSyntaxDepth) {
    throw new DocumentDomainError("template_resource_limit", "syntax_depth");
  }
  const nodes: TemplateNode[] = [];
  while (state.index < tokens.length) {
    const token = tokens[state.index];
    state.index += 1;
    if (!token) break;
    if (token.type === "tag" && terminators.has(token.value)) {
      return { nodes: Object.freeze(nodes), terminator: token.value };
    }
    let node: TemplateNode;
    if (token.type === "text") {
      node = Object.freeze({ type: "text", value: token.value });
    } else if (token.type === "output") {
      node = parseOutput(token.value);
    } else if (token.value.startsWith("if ")) {
      const condition = parseCondition(token.value.slice(3));
      const first = parseNodes(
        tokens,
        state,
        new Set(["else", "endif"]),
        depth + 1,
        loopDepth,
      );
      let alternate: readonly TemplateNode[] = Object.freeze([]);
      if (first.terminator === "else") {
        const second = parseNodes(
          tokens,
          state,
          new Set(["endif"]),
          depth + 1,
          loopDepth,
        );
        if (second.terminator !== "endif") {
          throw new DocumentDomainError("template_syntax_invalid", "if_end");
        }
        alternate = second.nodes;
      } else if (first.terminator !== "endif") {
        throw new DocumentDomainError("template_syntax_invalid", "if_end");
      }
      node = Object.freeze({
        type: "if",
        condition,
        consequent: first.nodes,
        alternate,
      });
    } else if (token.value.startsWith("for ")) {
      if (loopDepth >= DOCUMENT_TEMPLATE_LIMITS.maximumLoopDepth) {
        throw new DocumentDomainError("template_resource_limit", "loop_depth");
      }
      const match = /^for\s+([a-z][a-z0-9_]*)\s+in\s+(.+)$/u.exec(token.value);
      if (!match?.[1] || !match[2] || !LOOP_VARIABLE_PATTERN.test(match[1])) {
        throw new DocumentDomainError("template_syntax_invalid", "for");
      }
      const body = parseNodes(
        tokens,
        state,
        new Set(["endfor"]),
        depth + 1,
        loopDepth + 1,
      );
      if (body.terminator !== "endfor") {
        throw new DocumentDomainError("template_syntax_invalid", "for_end");
      }
      node = Object.freeze({
        type: "for",
        variable: match[1],
        collectionPath: assertPath(match[2]),
        body: body.nodes,
      });
    } else {
      throw new DocumentDomainError("template_syntax_invalid", token.value);
    }
    nodes.push(node);
    state.nodeCount += 1;
    if (state.nodeCount > DOCUMENT_TEMPLATE_LIMITS.maximumNodes) {
      throw new DocumentDomainError("template_resource_limit", "nodes");
    }
  }
  return { nodes: Object.freeze(nodes), terminator: null };
}

function injectCss(sourceHtml: string, sourceCss: string): string {
  if (!sourceCss.trim()) return sourceHtml;
  const style = `<style data-vynlo-template="true">${sourceCss}</style>`;
  return /<\/head\s*>/iu.test(sourceHtml)
    ? sourceHtml.replace(/<\/head\s*>/iu, `${style}</head>`)
    : `${style}${sourceHtml}`;
}

export function compileDocumentTemplate(
  value: unknown,
): CompiledDocumentTemplate {
  const sourceBundle = normalizeTemplateSourceBundle(value);
  const assetKeys = assertSafeSource(
    sourceBundle.sourceHtml,
    sourceBundle.sourceCss,
  );
  const availableAssets = new Set(
    sourceBundle.assets.map((asset) => asset.key),
  );
  const missingAsset = assetKeys.find((key) => !availableAssets.has(key));
  if (missingAsset) {
    throw new DocumentDomainError(
      "checksum_mismatch",
      `missing_asset:${missingAsset}`,
    );
  }
  const tokens = tokenize(
    injectCss(sourceBundle.sourceHtml, sourceBundle.sourceCss),
  );
  const state = { index: 0, nodeCount: 0 };
  const parsed = parseNodes(tokens, state, new Set(), 0, 0);
  if (parsed.terminator !== null || state.index !== tokens.length) {
    throw new DocumentDomainError("template_syntax_invalid", "unexpected_end");
  }
  const compiled: CompiledDocumentTemplate = Object.freeze({
    sourceChecksum: sourceBundle.checksum,
    sourceBundle,
    assetKeys,
    nodeCount: state.nodeCount,
    nodes: parsed.nodes,
  });
  COMPILED_TEMPLATES.add(compiled);
  return compiled;
}

const MISSING = Symbol("missing_template_value");
type ResolvedValue = unknown | typeof MISSING;

function resolvePath(
  path: string,
  root: PlainRecord,
  locals: Readonly<Record<string, unknown>>,
): ResolvedValue {
  const segments = path.split(".");
  const first = segments.shift();
  if (!first) return MISSING;
  let value: unknown = Object.hasOwn(locals, first)
    ? locals[first]
    : root[first];
  if (value === undefined) return MISSING;
  for (const segment of segments) {
    if (Array.isArray(value)) {
      if (!/^\d{1,4}$/u.test(segment)) return MISSING;
      value = value[Number(segment)];
    } else {
      const record = requirePlainRecord(value, "template_value_invalid");
      value = record[segment];
    }
    if (value === undefined) return MISSING;
  }
  return value;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function truthy(value: ResolvedValue): boolean {
  if (
    value === MISSING ||
    value === null ||
    value === false ||
    value === "" ||
    value === 0
  ) {
    return false;
  }
  return !Array.isArray(value) || value.length > 0;
}

function scalar(
  value: ResolvedValue,
): string | number | boolean | null | typeof MISSING {
  if (
    value === MISSING ||
    value === null ||
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    if (typeof value === "number" && !Number.isFinite(value)) {
      throw new DocumentDomainError("template_value_invalid", "number");
    }
    return value;
  }
  throw new DocumentDomainError("template_value_invalid", "scalar");
}

function formatDate(value: unknown, pattern: string): string {
  if (typeof value !== "string") {
    throw new DocumentDomainError("template_value_invalid", "date");
  }
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/u.exec(value);
  const parsed = dateOnly
    ? Date.parse(`${value}T00:00:00.000Z`)
    : Date.parse(normalizeIsoInstant(value, "template_value_invalid", "date"));
  const date = new Date(parsed);
  const year = String(date.getUTCFullYear()).padStart(4, "0");
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  if (dateOnly && `${year}-${month}-${day}` !== value) {
    throw new DocumentDomainError("template_value_invalid", "date");
  }
  return pattern.replace("%Y", year).replace("%m", month).replace("%d", day);
}

function formatMoney(
  value: unknown,
  currency: string,
  exponent: number,
): string {
  if (typeof value !== "string" || !MONEY_MINOR_PATTERN.test(value)) {
    throw new DocumentDomainError("template_value_invalid", "money");
  }
  const parsed = BigInt(value);
  if (parsed < POSTGRES_BIGINT_MIN || parsed > POSTGRES_BIGINT_MAX) {
    throw new DocumentDomainError("template_value_invalid", "money");
  }
  const negative = parsed < 0n;
  const absolute = negative ? -parsed : parsed;
  const divisor = 10n ** BigInt(exponent);
  const whole = (absolute / divisor).toString();
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/gu, ",");
  const fraction =
    exponent === 0
      ? ""
      : `.${(absolute % divisor).toString().padStart(exponent, "0")}`;
  return `${negative ? "-" : ""}${currency} ${grouped}${fraction}`;
}

function renderOutput(
  node: OutputNode,
  root: PlainRecord,
  locals: Readonly<Record<string, unknown>>,
): string {
  let value: ResolvedValue = resolvePath(node.path, root, locals);
  for (const filter of node.filters) {
    if (filter.name === "default") {
      if (!truthy(value)) value = filter.arguments[0] ?? "";
    } else if (filter.name === "date") {
      if (value === MISSING || value === null) {
        throw new DocumentDomainError("template_field_missing", node.path);
      }
      value = formatDate(value, String(filter.arguments[0]));
    } else {
      if (value === MISSING || value === null) {
        throw new DocumentDomainError("template_field_missing", node.path);
      }
      value = formatMoney(
        value,
        String(filter.arguments[0]),
        Number(filter.arguments[1] ?? 2),
      );
    }
  }
  const normalized = scalar(value);
  if (normalized === MISSING) {
    throw new DocumentDomainError("template_field_missing", node.path);
  }
  return escapeHtml(normalized === null ? "" : String(normalized));
}

function conditionMatches(
  condition: ConditionNode,
  root: PlainRecord,
  locals: Readonly<Record<string, unknown>>,
): boolean {
  const value = resolvePath(condition.path, root, locals);
  let result: boolean;
  if (condition.operator === "truthy") {
    result = truthy(value);
  } else {
    const comparable = scalar(value);
    result = comparable !== MISSING && comparable === condition.literal;
    if (condition.operator === "not_equal") result = !result;
  }
  return condition.negate ? !result : result;
}

function renderNodes(
  nodes: readonly TemplateNode[],
  root: PlainRecord,
  locals: Readonly<Record<string, unknown>>,
  state: { iterations: number; outputBytes: number },
): string {
  let output = "";
  const append = (value: string) => {
    state.outputBytes += new TextEncoder().encode(value).byteLength;
    if (state.outputBytes > DOCUMENT_TEMPLATE_LIMITS.maximumOutputBytes) {
      throw new DocumentDomainError("template_resource_limit", "output_bytes");
    }
    output += value;
  };
  for (const node of nodes) {
    if (node.type === "text") {
      append(node.value);
    } else if (node.type === "output") {
      append(renderOutput(node, root, locals));
    } else if (node.type === "if") {
      output += renderNodes(
        conditionMatches(node.condition, root, locals)
          ? node.consequent
          : node.alternate,
        root,
        locals,
        state,
      );
    } else {
      const collection = resolvePath(node.collectionPath, root, locals);
      if (!Array.isArray(collection)) {
        throw new DocumentDomainError(
          "template_value_invalid",
          node.collectionPath,
        );
      }
      if (collection.length > DOCUMENT_TEMPLATE_LIMITS.maximumLoopItems) {
        throw new DocumentDomainError("template_resource_limit", "loop_items");
      }
      for (const item of collection) {
        state.iterations += 1;
        if (
          state.iterations > DOCUMENT_TEMPLATE_LIMITS.maximumRenderIterations
        ) {
          throw new DocumentDomainError(
            "template_resource_limit",
            "iterations",
          );
        }
        output += renderNodes(
          node.body,
          root,
          Object.freeze({ ...locals, [node.variable]: item }),
          state,
        );
      }
    }
  }
  return output;
}

export function renderDocumentTemplate(
  compiled: CompiledDocumentTemplate,
  input: unknown,
): Readonly<{ html: string; checksum: string; renderedBytes: number }> {
  if (
    typeof compiled !== "object" ||
    compiled === null ||
    !COMPILED_TEMPLATES.has(compiled)
  ) {
    throw new DocumentDomainError(
      "unsafe_template_source",
      "untrusted_compilation",
    );
  }
  const root = requirePlainRecord(input, "template_value_invalid");
  // Validates nested values, accessors, prototypes, cycles, size, and non-finite numbers.
  canonicalJson(root);
  const state = { iterations: 0, outputBytes: 0 };
  const html = renderNodes(compiled.nodes, root, Object.freeze({}), state);
  return Object.freeze({
    html,
    checksum: sha256Hex(html),
    renderedBytes: state.outputBytes,
  });
}
