// Stable test IDs: T-DOC-001, T-DOC-006.
import { describe, expect, it } from "vitest";

import { DocumentDomainError, sha256Hex } from "./domain-common";
import {
  compileDocumentTemplate,
  computeTemplateSourceBundleChecksum,
  DOCUMENT_TEMPLATE_LIMITS,
  renderDocumentTemplate,
} from "./template-runtime";

function pngAsset() {
  const content = new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00,
  ]);
  return Object.freeze({
    key: "brand.logo",
    filename: "logo.png",
    mimeType: "image/png",
    byteSize: content.byteLength,
    checksum: sha256Hex(content),
    content,
  });
}

function bundle(
  sourceHtml: string,
  sourceCss = "",
  assets: readonly ReturnType<typeof pngAsset>[] = [],
) {
  return {
    sourceHtml,
    sourceCss,
    assets,
    checksum: computeTemplateSourceBundleChecksum({
      sourceHtml,
      sourceCss,
      assets,
    }),
  };
}

describe("T-DOC-001 / T-DOC-006 bounded document template runtime", () => {
  it("renders escaped values, if/else, bounded rows, and allowlisted helpers", () => {
    const sourceHtml = `<!doctype html><html><head></head><body>
      <img src="vynlo-asset:brand.logo" alt="">
      <h1>{{ customer.name }}</h1>
      {% if customer.active %}<p>Active</p>{% else %}<p>Inactive</p>{% endif %}
      {% for line in lines %}
        <span>{{ line.label | default: "—" }}</span>
        <time>{{ line.date | date: "%Y-%m-%d" }}</time>
        <data>{{ line.amount_minor | money: "CAD", 2 }}</data>
      {% endfor %}
    </body></html>`;
    const compiled = compileDocumentTemplate(
      bundle(sourceHtml, "body { color: #111; }", [pngAsset()]),
    );
    const result = renderDocumentTemplate(compiled, {
      customer: { active: false, name: "<Alice & Bob>" },
      lines: [
        { amount_minor: "123456", date: "2026-07-16", label: "" },
        { amount_minor: "-25", date: "2026-07-17", label: "Fee" },
      ],
    });

    expect(result.html).toContain("&lt;Alice &amp; Bob&gt;");
    expect(result.html).toContain("<p>Inactive</p>");
    expect(result.html).toContain("—");
    expect(result.html).toContain("CAD 1,234.56");
    expect(result.html).toContain("-CAD 0.25");
    expect(result.html).toContain('data-vynlo-template="true"');
    expect(result.checksum).toBe(sha256Hex(result.html));
    expect(compiled.assetKeys).toEqual(["brand.logo"]);
    expect(compiled.sourceBundle.assets[0]?.content).toBe("89504e470d0a1a0a00");
    expect(Object.isFrozen(compiled.sourceBundle.assets[0])).toBe(true);
  });

  it("supports deterministic comparisons, negation, and alternate branches", () => {
    const compiled = compileDocumentTemplate(
      bundle(
        `{% if kind == "retail" %}R{% else %}X{% endif %}` +
          `{% if not hidden %}V{% endif %}` +
          `{% if count != 2 %}N{% endif %}`,
      ),
    );
    expect(
      renderDocumentTemplate(compiled, {
        count: 3,
        hidden: false,
        kind: "retail",
      }).html,
    ).toBe("RVN");
  });

  it("verifies source-bundle and asset bytes before compilation", () => {
    const valid = bundle("<p>Safe</p>", "", [pngAsset()]);
    const tamperedAsset = {
      ...pngAsset(),
      content: new Uint8Array([0x89, 0x50]),
      byteSize: 2,
      checksum: sha256Hex(new Uint8Array([0x89, 0x50])),
    };
    expect(() =>
      compileDocumentTemplate({ ...valid, checksum: "a".repeat(64) }),
    ).toThrowError(expect.objectContaining({ code: "checksum_mismatch" }));
    expect(() =>
      compileDocumentTemplate({
        ...valid,
        assets: [tamperedAsset],
        checksum: computeTemplateSourceBundleChecksum({
          sourceHtml: valid.sourceHtml,
          sourceCss: valid.sourceCss,
          assets: [tamperedAsset],
        }),
      }),
    ).toThrowError(expect.objectContaining({ code: "unsafe_template_source" }));
  });

  it.each([
    ["script", '<script src="vynlo-asset:brand.logo"></script>'],
    ["event handler", '<img src="vynlo-asset:brand.logo" onload="alert(1)">'],
    ["remote SSRF", '<img src="https://example.invalid/a.png">'],
    ["metadata SSRF", '<img src="http://169.254.169.254/latest/meta-data">'],
    ["localhost SSRF", '<img src="http://localhost:8080/private">'],
    ["filesystem", '<img src="file:///etc/passwd">'],
    ["data URL", '<img src="data:image/png;base64,AAAA">'],
    [
      "remote stylesheet",
      '<link rel="stylesheet" href="https://example.invalid/a.css">',
    ],
    [
      "source set",
      '<img src="vynlo-asset:brand.logo" srcset="vynlo-asset:brand.logo 1x, https://example.invalid/a.png 2x">',
    ],
    [
      "form action override",
      '<input type="submit" formaction="https://example.invalid">',
    ],
    ["dynamic tag", "<{{ element }}>unsafe</{{ element }}>"],
    ["dynamic attribute", "<div {{ attribute }}>unsafe</div>"],
    ["dynamic style attribute", '<div style="color:{{ color }}">unsafe</div>'],
    ["dynamic style block", "<style>x{color:{{ color }}}</style>"],
    ["CSS import", "<style>@import 'https://example.invalid/a.css';</style>"],
    ["CSS local URL", '<style>x{background:url("http://127.0.0.1/a")}</style>'],
    ["executable CSS", "<style>x{width:expression(alert(1))}</style>"],
    [
      "CSS image set",
      '<style>x{background:image-set(url("vynlo-asset:brand.logo") 1x)}</style>',
    ],
    ["local font lookup", '<style>@font-face{src:local("Arial")}</style>'],
    [
      "form submission",
      '<form action="https://example.invalid"><input></form>',
    ],
  ])("rejects the %s attack before parsing", (_label, sourceHtml) => {
    expect(() =>
      compileDocumentTemplate(bundle(sourceHtml, "", [pngAsset()])),
    ).toThrowError(expect.objectContaining({ code: "unsafe_template_source" }));
  });

  it.each([
    ["remote URL", 'x{background:url("https://example.invalid/a.png")}'],
    ["import", "@import 'https://example.invalid/a.css';"],
    [
      "escaped URL token",
      'x{background:u\\72l("https://example.invalid/a.png")}',
    ],
    ["dynamic CSS", "x{color:{{ color }}}"],
    ["local font", '@font-face{src:local("Arial")}'],
  ])("rejects %s in the dedicated CSS source", (_label, sourceCss) => {
    expect(() =>
      compileDocumentTemplate(bundle("<p>Safe</p>", sourceCss, [pngAsset()])),
    ).toThrowError(expect.objectContaining({ code: "unsafe_template_source" }));
  });

  it.each([
    ["function expression", "{{ customer.name() }}"],
    ["prototype path", "{{ customer.constructor.name }}"],
    ["unknown helper", '{{ customer.name | fetch: "x" }}'],
    ["unclosed output", "{{ customer.name"],
    ["orphan branch", "{% else %}"],
    ["unsupported comment", "{# hidden #}"],
    ["unbounded syntax", "{% for item in rows %}x"],
  ])("rejects %s syntax fail-closed", (_label, sourceHtml) => {
    expect(() => compileDocumentTemplate(bundle(sourceHtml))).toThrowError(
      DocumentDomainError,
    );
  });

  it("rejects missing fields, object output, getters, and invalid helper values", () => {
    const missing = compileDocumentTemplate(bundle("{{ missing }}"));
    expect(() => renderDocumentTemplate(missing, {})).toThrowError(
      expect.objectContaining({ code: "template_field_missing" }),
    );
    const objectOutput = compileDocumentTemplate(bundle("{{ customer }}"));
    expect(() =>
      renderDocumentTemplate(objectOutput, { customer: { name: "A" } }),
    ).toThrowError(expect.objectContaining({ code: "template_value_invalid" }));
    const getter = Object.defineProperty({}, "customer", {
      get: () => "secret",
    });
    expect(() => renderDocumentTemplate(missing, getter)).toThrowError(
      expect.objectContaining({ code: "arbitrary_execution_not_allowed" }),
    );
    const money = compileDocumentTemplate(
      bundle('{{ amount | money: "CAD" }}'),
    );
    expect(() =>
      renderDocumentTemplate(money, { amount: "1.25" }),
    ).toThrowError(expect.objectContaining({ code: "template_value_invalid" }));

    const rows: unknown[] = [];
    let getterCalls = 0;
    Object.defineProperty(rows, "0", {
      enumerable: true,
      get: () => {
        getterCalls += 1;
        return "secret";
      },
    });
    rows.length = 1;
    const loop = compileDocumentTemplate(
      bundle("{% for row in rows %}{{ row }}{% endfor %}"),
    );
    expect(() => renderDocumentTemplate(loop, { rows })).toThrowError(
      expect.objectContaining({ code: "arbitrary_execution_not_allowed" }),
    );
    expect(getterCalls).toBe(0);
  });

  it("renders only compiler-issued immutable templates", () => {
    const compiled = compileDocumentTemplate(bundle("<p>{{ name }}</p>"));
    expect(() =>
      renderDocumentTemplate({ ...compiled }, { name: "Alice" }),
    ).toThrowError(expect.objectContaining({ code: "unsafe_template_source" }));
  });

  it("enforces loop, nesting, source, and rendered-output limits", () => {
    const loop = compileDocumentTemplate(
      bundle("{% for row in rows %}x{% endfor %}"),
    );
    expect(() =>
      renderDocumentTemplate(loop, {
        rows: Array.from(
          { length: DOCUMENT_TEMPLATE_LIMITS.maximumLoopItems + 1 },
          () => 1,
        ),
      }),
    ).toThrowError(
      expect.objectContaining({ code: "template_resource_limit" }),
    );

    const tooDeep =
      "{% for a in rows %}{% for b in rows %}{% for c in rows %}{% for d in rows %}" +
      "{% for e in rows %}x{% endfor %}{% endfor %}{% endfor %}{% endfor %}{% endfor %}";
    expect(() => compileDocumentTemplate(bundle(tooDeep))).toThrowError(
      expect.objectContaining({ code: "template_resource_limit" }),
    );

    const largeText = "x".repeat(900_000);
    const output = compileDocumentTemplate(
      bundle(`{% for row in rows %}${largeText}{% endfor %}`),
    );
    expect(() =>
      renderDocumentTemplate(output, { rows: [1, 2, 3, 4, 5, 6] }),
    ).toThrowError(
      expect.objectContaining({ code: "template_resource_limit" }),
    );
    expect(() =>
      compileDocumentTemplate(bundle("x".repeat(1_000_001))),
    ).toThrowError(
      expect.objectContaining({ code: "template_resource_limit" }),
    );
  });

  it("requires every asset reference to match the checksummed manifest", () => {
    expect(() =>
      compileDocumentTemplate(bundle('<img src="vynlo-asset:brand.logo">')),
    ).toThrowError(expect.objectContaining({ code: "checksum_mismatch" }));
  });
});
