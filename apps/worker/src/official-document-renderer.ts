import { Buffer } from "node:buffer";

import {
  compileDocumentTemplate,
  computeTemplateSourceBundleChecksum,
  officialDocumentPdfFilename,
  renderDocumentTemplate,
  type DocumentTemplateAsset,
} from "@vynlo/documents";

import { artifactSha256Hex } from "./immutable-artifact-storage";
import { JobExecutionError } from "./job-runner";
import {
  CHECKSUM_PATTERN,
  requireArray,
  requireRecord,
  UUID_PATTERN,
} from "./m4-worker-validation";

export const OFFICIAL_DOCUMENT_JOB_TYPE = "documents.render_pdf" as const;
export const OFFICIAL_PDF_RENDERER_VERSION = "playwright-pdf-v1" as const;
export const OFFICIAL_PDF_CONTENT_TYPE = "application/pdf" as const;
const MAXIMUM_PDF_BYTES = 52_428_800;

export interface OfficialDocumentRenderSource {
  readonly assetManifest: Readonly<Record<string, unknown>>;
  readonly documentId: string;
  readonly fontManifest: Readonly<Record<string, unknown>>;
  readonly locale: string;
  readonly officialNumber: string;
  readonly renderInputChecksum: string;
  readonly renderInputSnapshot: Readonly<Record<string, unknown>>;
  readonly rendererVersion: string;
  readonly sourceBundleChecksum: string;
  readonly sourceCss: string;
  readonly sourceHtml: string;
  readonly versionSnapshot: Readonly<Record<string, unknown>>;
  readonly versionSnapshotChecksum: string;
}

export interface RenderedOfficialPdf {
  readonly body: Uint8Array;
  readonly byteSize: number;
  readonly checksum: string;
  readonly contentType: typeof OFFICIAL_PDF_CONTENT_TYPE;
  readonly filename: string;
  readonly rendererVersion: typeof OFFICIAL_PDF_RENDERER_VERSION;
}

export interface PdfEngine {
  render(input: {
    readonly html: string;
    readonly locale: string;
    readonly signal: AbortSignal;
    readonly timeoutMs: number;
  }): Promise<Uint8Array>;
}

function manifestAssets(
  manifest: Readonly<Record<string, unknown>>,
  label: string,
): readonly unknown[] {
  const keys = Object.keys(manifest);
  if (keys.length === 0) return [];
  if (keys.length !== 1 || keys[0] !== "assets") {
    throw new JobExecutionError({
      classification: "validation",
      code: "document.asset_manifest_invalid",
      safeDetail: "The official template asset manifest is not supported.",
    });
  }
  return requireArray(manifest.assets, "document", label);
}

function templateAssets(
  source: OfficialDocumentRenderSource,
): readonly DocumentTemplateAsset[] {
  return [
    ...manifestAssets(source.assetManifest, "asset_manifest"),
    ...manifestAssets(source.fontManifest, "font_manifest"),
  ] as readonly DocumentTemplateAsset[];
}

function renderInput(
  source: OfficialDocumentRenderSource,
): Readonly<Record<string, unknown>> {
  const document = requireRecord(
    source.renderInputSnapshot.document,
    "document",
    "render_input_document",
  );
  return Object.freeze({
    ...source.renderInputSnapshot,
    document: Object.freeze({
      ...document,
      official_number: source.officialNumber,
    }),
  });
}

function assertSafeNumericTransport(
  value: unknown,
  state = { nodes: 0 },
  depth = 0,
): void {
  state.nodes += 1;
  if (state.nodes > 20_000 || depth > 64) {
    throw new JobExecutionError({
      classification: "validation",
      code: "document.render_input_resource_limit",
      safeDetail:
        "The official render input exceeds its bounded JSON contract.",
    });
  }
  if (typeof value === "number") {
    if (
      !Number.isFinite(value) ||
      (Number.isInteger(value) && !Number.isSafeInteger(value))
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "document.render_input_number_unsafe",
        safeDetail:
          "The official render input contains an inexact numeric transport value.",
      });
    }
    return;
  }
  if (typeof value !== "object" || value === null) return;
  for (const key of Object.keys(value)) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor === undefined || !("value" in descriptor)) {
      throw new JobExecutionError({
        classification: "validation",
        code: "document.render_input_accessor_rejected",
        safeDetail:
          "The official render input contains an unsafe property accessor.",
      });
    }
    assertSafeNumericTransport(descriptor.value, state, depth + 1);
  }
}

function dataUrl(asset: DocumentTemplateAsset): string {
  return `data:${asset.mimeType};base64,${Buffer.from(asset.content, "hex").toString("base64")}`;
}

function injectAssets(
  html: string,
  assets: readonly DocumentTemplateAsset[],
): string {
  let result = html;
  for (const asset of assets) {
    result = result.replaceAll(`vynlo-asset:${asset.key}`, dataUrl(asset));
  }
  if (result.includes("vynlo-asset:")) {
    throw new JobExecutionError({
      classification: "validation",
      code: "document.asset_reference_unresolved",
      safeDetail:
        "The official template contains an unresolved approved asset.",
    });
  }
  return result;
}

function browserDocument(html: string): string {
  const policy =
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline';\">";
  if (/<head(?:\s[^>]*)?>/iu.test(html)) {
    return html.replace(/<head(?:\s[^>]*)?>/iu, (head) => head + policy);
  }
  if (/<html(?:\s[^>]*)?>/iu.test(html)) {
    return html.replace(
      /<html(?:\s[^>]*)?>/iu,
      (root) => `${root}<head>${policy}</head>`,
    );
  }
  return `<!doctype html><html><head>${policy}</head><body>${html}</body></html>`;
}

/**
 * Chromium timestamps are not business input. Replacing only same-width date
 * digits preserves PDF offsets while making retry output byte-stable.
 */
export function canonicalizePdfBytes(input: Uint8Array): Uint8Array {
  let value = Buffer.from(input).toString("latin1");
  value = value.replace(
    /(\/(?:CreationDate|ModDate) \(D:)\d{14}/gu,
    (_match, prefix: string) => `${prefix}20000101000000`,
  );
  value = value.replace(
    /((?:xmp:CreateDate|xmp:ModifyDate|xmp:MetadataDate)=["'])\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/gu,
    (_match, prefix: string) => `${prefix}2000-01-01T00:00:00`,
  );
  return new Uint8Array(Buffer.from(value, "latin1"));
}

export function assertGenuinePdf(value: Uint8Array): void {
  const prefix = Buffer.from(value.subarray(0, 8)).toString("ascii");
  const suffix = Buffer.from(
    value.subarray(Math.max(0, value.byteLength - 1_024)),
  ).toString("latin1");
  if (
    value.byteLength < 100 ||
    value.byteLength > MAXIMUM_PDF_BYTES ||
    !prefix.startsWith("%PDF-") ||
    !suffix.includes("%%EOF")
  ) {
    throw new JobExecutionError({
      classification: "permanent",
      code: "document.pdf_artifact_invalid",
      safeDetail: "The PDF engine returned an invalid bounded artifact.",
    });
  }
}

export class PlaywrightPdfEngine implements PdfEngine {
  async render(input: {
    readonly html: string;
    readonly locale: string;
    readonly signal: AbortSignal;
    readonly timeoutMs: number;
  }): Promise<Uint8Array> {
    if (input.signal.aborted) {
      throw new JobExecutionError({
        classification: "transient",
        code: "document.pdf_render_cancelled",
        safeDetail: "The official PDF render was cancelled with its job lease.",
      });
    }
    let browser: { close(): Promise<void> } | undefined;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    const abort = () => void browser?.close().catch(() => undefined);
    input.signal.addEventListener("abort", abort, { once: true });
    try {
      const { chromium } = await import("playwright");
      const operation = (async () => {
        const launched = await chromium.launch({ headless: true });
        browser = launched;
        const context = await launched.newContext({
          javaScriptEnabled: false,
          locale: input.locale,
        });
        await context.route("**/*", async (route) => {
          const protocol = new URL(route.request().url()).protocol;
          if (protocol === "about:" || protocol === "data:") {
            await route.continue();
          } else {
            await route.abort("blockedbyclient");
          }
        });
        const page = await context.newPage();
        page.setDefaultTimeout(input.timeoutMs);
        await page.setContent(input.html, { waitUntil: "load" });
        await page.emulateMedia({ media: "print" });
        const pdf = await page.pdf({
          format: "Letter",
          margin: { bottom: "12mm", left: "12mm", right: "12mm", top: "12mm" },
          preferCSSPageSize: true,
          printBackground: true,
          tagged: true,
        });
        return new Uint8Array(pdf);
      })();
      return await Promise.race([
        operation,
        new Promise<never>((_resolve, reject) => {
          timeout = setTimeout(() => {
            void browser?.close().catch(() => undefined);
            reject(
              new JobExecutionError({
                classification: "transient",
                code: "document.pdf_render_timeout",
                safeDetail: "The bounded official PDF render timed out.",
              }),
            );
          }, input.timeoutMs);
        }),
      ]);
    } catch (error) {
      if (error instanceof JobExecutionError) throw error;
      throw new JobExecutionError({
        classification: "transient",
        code: "document.pdf_runtime_unavailable",
        safeDetail: "The approved headless PDF runtime is unavailable.",
      });
    } finally {
      if (timeout !== undefined) clearTimeout(timeout);
      input.signal.removeEventListener("abort", abort);
      await browser?.close().catch(() => undefined);
    }
  }
}

export class OfficialDocumentRenderer {
  readonly #engine: PdfEngine;
  readonly #timeoutMs: number;

  constructor(input: {
    readonly engine?: PdfEngine;
    readonly timeoutMs: number;
  }) {
    if (
      !Number.isInteger(input.timeoutMs) ||
      input.timeoutMs < 1_000 ||
      input.timeoutMs > 120_000
    ) {
      throw new RangeError(
        "Official PDF timeout must be from 1000 to 120000ms.",
      );
    }
    this.#engine = input.engine ?? new PlaywrightPdfEngine();
    this.#timeoutMs = input.timeoutMs;
  }

  async render(
    source: OfficialDocumentRenderSource,
    signal: AbortSignal,
  ): Promise<RenderedOfficialPdf> {
    if (
      source.rendererVersion !== OFFICIAL_PDF_RENDERER_VERSION ||
      !CHECKSUM_PATTERN.test(source.sourceBundleChecksum) ||
      !CHECKSUM_PATTERN.test(source.renderInputChecksum) ||
      !CHECKSUM_PATTERN.test(source.versionSnapshotChecksum)
    ) {
      throw new JobExecutionError({
        classification: "validation",
        code: "document.render_snapshot_invalid",
        safeDetail:
          "The official render snapshot uses an unsupported renderer contract.",
      });
    }
    assertSafeNumericTransport(source.renderInputSnapshot);
    assertSafeNumericTransport(source.versionSnapshot);
    const assets = templateAssets(source);
    const computedSourceBundleChecksum = computeTemplateSourceBundleChecksum({
      assets,
      sourceCss: source.sourceCss,
      sourceHtml: source.sourceHtml,
    });
    if (computedSourceBundleChecksum !== source.sourceBundleChecksum) {
      throw new JobExecutionError({
        classification: "validation",
        code: "document.source_bundle_checksum_mismatch",
        safeDetail:
          "The official template source differs from its immutable checksum.",
      });
    }
    const bundle = {
      assets,
      checksum: computedSourceBundleChecksum,
      sourceCss: source.sourceCss,
      sourceHtml: source.sourceHtml,
    };
    const compiled = compileDocumentTemplate(bundle);
    const rendered = renderDocumentTemplate(compiled, renderInput(source));
    const html = browserDocument(
      injectAssets(rendered.html, compiled.sourceBundle.assets),
    );
    const body = canonicalizePdfBytes(
      await this.#engine.render({
        html,
        locale: source.locale,
        signal,
        timeoutMs: this.#timeoutMs,
      }),
    );
    assertGenuinePdf(body);
    const checksum = artifactSha256Hex(body);
    return Object.freeze({
      body,
      byteSize: body.byteLength,
      checksum,
      contentType: OFFICIAL_PDF_CONTENT_TYPE,
      filename: officialDocumentPdfFilename(source.officialNumber),
      rendererVersion: OFFICIAL_PDF_RENDERER_VERSION,
    });
  }
}

export function officialDocumentStoragePath(input: {
  readonly artifactChecksum: string;
  readonly documentId: string;
  readonly workspaceId: string;
}): string {
  if (
    !CHECKSUM_PATTERN.test(input.artifactChecksum) ||
    !UUID_PATTERN.test(input.documentId) ||
    !UUID_PATTERN.test(input.workspaceId)
  ) {
    throw new TypeError("Invalid official document storage checksum.");
  }
  return `${input.workspaceId}/documents/${input.documentId}/generated_original/v1/${input.artifactChecksum}.pdf`;
}
