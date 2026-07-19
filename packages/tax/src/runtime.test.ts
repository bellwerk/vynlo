import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  TaxRuntimeError,
  compileTaxPack,
  createCalculationTaxPort,
  decideTaxPackAvailability,
  executeTaxCalculation,
  runTaxGoldenCases,
  selectTaxPack,
  type TaxCalculationRequest,
  type TaxPackDefinition,
  type TaxPackSelector,
} from "./runtime";

const CANDIDATE_PACK = {
  key: "tax-ca-qc",
  version: "1.0.0",
  jurisdiction: "CA-QC",
  contexts: [
    "vehicle_retail_sale",
    "vehicle_wholesale_sale",
    "vehicle_purchase",
    "taxable_service_fee",
  ],
  effective_from: "2026-07-15",
  effective_to: null,
  sources: [
    {
      key: "revenu_quebec_basic_gst_qst",
      authority: "Revenu Québec",
      url: "https://www.revenuquebec.ca/en/businesses/consumption-taxes/gsthst-and-qst/basic-rules-for-applying-the-gsthst-and-qst/",
      accessed_on: "2026-07-15",
    },
    {
      key: "revenu_quebec_used_vehicle_trade_ins",
      authority: "Revenu Québec",
      url: "https://www.revenuquebec.ca/en/businesses/consumption-taxes/gsthst-and-qst/special-cases-gsthst-and-qst/transportation-applying-the-gst-and-qst/road-vehicles-businesses/trade-ins-of-used-road-vehicles/purchaser-not-required-to-collect-the-gst-or-calculate-or-collect-the-qst/",
      accessed_on: "2026-07-15",
    },
  ],
  rules: {
    currency: "CAD",
    rounding: {
      mode: "HALF_UP",
      scale: 2,
      stage: "tax_total_per_tax_type",
    },
    taxes: [
      {
        key: "gst",
        labels: { en: "GST", fr: "TPS" },
        rate: "0.05",
        taxable_base: "eligible_taxable_consideration",
        source_ref: "revenu_quebec_basic_gst_qst",
      },
      {
        key: "qst",
        labels: { en: "QST", fr: "TVQ" },
        rate: "0.09975",
        taxable_base: "eligible_taxable_consideration",
        gst_included_in_base: false,
        source_ref: "revenu_quebec_basic_gst_qst",
      },
    ],
    trade_in: {
      strategy: "conditional_credit_reduces_taxable_consideration",
      requires_explicit_eligibility_inputs: true,
      lien_payoff_is_not_automatically_tax_credit: true,
    },
    unsupported_without_override: [
      "cross_border_sale",
      "exempt_purchaser",
      "unusual_vehicle_category",
      "multiple_tax_jurisdictions",
    ],
  },
  golden_tests: [
    "tests/vehicle-sale-no-trade-in.json",
    "tests/taxable-discount.json",
    "tests/eligible-trade-in.json",
  ],
  activation_status: "draft",
  approval_refs: [],
} as const satisfies TaxPackDefinition;

const GOLDEN_CASES = [
  "vehicle-sale-no-trade-in.json",
  "taxable-discount.json",
  "eligible-trade-in.json",
].map(
  (name) =>
    JSON.parse(
      readFileSync(
        new URL(`../../../packs/tax/ca-qc/tests/${name}`, import.meta.url),
        "utf8",
      ),
    ) as Record<string, unknown>,
);

function candidatePack(
  overrides: Readonly<Record<string, unknown>> = {},
): unknown {
  return { ...CANDIDATE_PACK, ...overrides };
}

function activePack(key: string = CANDIDATE_PACK.key) {
  return compileTaxPack(
    candidatePack({
      key,
      activation_status: "active",
      approval_refs: ["professional-review:synthetic"],
    }),
  );
}

function selector(overrides: Partial<TaxPackSelector> = {}): TaxPackSelector {
  return {
    jurisdiction: "CA-QC",
    context: "vehicle_retail_sale",
    transactionDate: "2026-07-15",
    currency: "CAD",
    usage: "preview",
    ...overrides,
  };
}

function request(
  input: TaxCalculationRequest["input"],
  overrides: Partial<Omit<TaxCalculationRequest, "input">> = {},
): TaxCalculationRequest {
  return {
    jurisdiction: "CA-QC",
    context: "vehicle_retail_sale",
    transactionDate: "2026-07-15",
    currency: "CAD",
    input,
    ...overrides,
  };
}

function taxCode(action: () => unknown): string | undefined {
  try {
    action();
    return undefined;
  } catch (error) {
    return error instanceof TaxRuntimeError ? error.code : undefined;
  }
}

describe("T-TAX-001 explicit selection and exact version snapshots", () => {
  it("keeps the immutable pack checksum stable across lifecycle and approvals", () => {
    const draft = compileTaxPack(
      candidatePack({ activation_status: "draft", approval_refs: [] }),
    );
    const active = compileTaxPack(
      candidatePack({
        activation_status: "active",
        approval_refs: ["approval-1"],
      }),
    );

    expect(active.checksum).toBe(draft.checksum);
    expect(active.definition.activation_status).toBe("active");
    expect(active.definition.approval_refs).toEqual(["approval-1"]);
  });

  it("compiles a deterministic candidate and selects it only from explicit context", () => {
    const first = compileTaxPack(CANDIDATE_PACK);
    const second = compileTaxPack(
      JSON.parse(JSON.stringify(CANDIDATE_PACK)) as unknown,
    );
    expect(first.checksum).toBe(second.checksum);
    expect(first.checksum).toMatch(/^[0-9a-f]{64}$/u);
    expect(Object.isFrozen(first.definition.rules.taxes)).toBe(true);

    const decision = decideTaxPackAvailability(first, selector());
    expect(decision).toEqual({
      state: "available_for_preview",
      available: true,
      gates: [],
      packKey: "tax-ca-qc",
      packVersion: "1.0.0",
      packChecksum: first.checksum,
    });
    expect(selectTaxPack([first], selector())).toBe(first);
  });

  it("executes the real candidate JSON golden files and pins all pack evidence", () => {
    const pack = compileTaxPack(CANDIDATE_PACK);
    const results = runTaxGoldenCases(pack, GOLDEN_CASES);

    expect(
      results.map(({ caseId, passed, mismatches }) => ({
        caseId,
        passed,
        mismatches,
      })),
    ).toEqual([
      {
        caseId: "CA-QC-VEHICLE-SALE-001",
        passed: true,
        mismatches: [],
      },
      {
        caseId: "CA-QC-VEHICLE-SALE-DISCOUNT-001",
        passed: true,
        mismatches: [],
      },
      {
        caseId: "CA-QC-VEHICLE-SALE-TRADEIN-001",
        passed: true,
        mismatches: [],
      },
    ]);
    expect(results[0]?.snapshot.output).toEqual({
      eligible_taxable_consideration_minor: "1000000",
      gst_minor: "50000",
      net_cash_consideration_before_payments_minor: "1149750",
      non_taxable_fees_minor: "0",
      qst_minor: "99750",
      total_tax_minor: "149750",
    });
    expect(results[0]?.snapshot.input).toEqual({
      eligible_trade_in_credit_minor: "0",
      non_taxable_fees_minor: "0",
      taxable_fees_minor: "0",
      trade_in_eligibility: null,
      vehicle_price_minor: "1000000",
    });
    expect(results[1]?.snapshot.input).toEqual({
      eligible_trade_in_credit_minor: "0",
      non_taxable_discounts_minor: "0",
      non_taxable_fees_minor: "0",
      taxable_discounts_minor: "50000",
      taxable_fees_minor: "0",
      trade_in_eligibility: null,
      vehicle_price_minor: "1000000",
    });
    expect(results[1]?.snapshot.output).toEqual({
      eligible_taxable_consideration_minor: "950000",
      gst_minor: "47500",
      net_cash_consideration_before_payments_minor: "1092263",
      non_taxable_fees_minor: "0",
      qst_minor: "94763",
      total_tax_minor: "142263",
    });
    expect(results[2]?.snapshot.output).toEqual({
      eligible_taxable_consideration_minor: "700000",
      gst_minor: "35000",
      net_cash_consideration_before_payments_minor: "804825",
      non_taxable_fees_minor: "0",
      qst_minor: "69825",
      total_tax_minor: "104825",
    });
    expect(results[0]?.snapshot.pack).toEqual(pack.definition);
    expect(Object.isFrozen(results[0]?.snapshot.output)).toBe(true);
    expect(results[0]?.snapshot.checksum).toMatch(/^[0-9a-f]{64}$/u);
    expect(runTaxGoldenCases(pack, GOLDEN_CASES)).toEqual(results);
  });

  it("rounds each tax independently in minor units and excludes GST from QST base", () => {
    const snapshot = executeTaxCalculation(
      compileTaxPack(CANDIDATE_PACK),
      request({ eligible_taxable_consideration_minor: "10" }),
    );
    expect(snapshot.output).toEqual({
      eligible_taxable_consideration_minor: "10",
      gst_minor: "1",
      net_cash_consideration_before_payments_minor: "12",
      non_taxable_fees_minor: "0",
      qst_minor: "1",
      total_tax_minor: "2",
    });
  });

  it("subtracts explicitly classified discounts from their own exact-money buckets", () => {
    const snapshot = executeTaxCalculation(
      compileTaxPack(CANDIDATE_PACK),
      request({
        vehicle_price_minor: "1000000",
        taxable_fees_minor: "2500",
        taxable_discounts_minor: "50000",
        non_taxable_fees_minor: "1000",
        non_taxable_discounts_minor: "1500",
        eligible_trade_in_credit_minor: "0",
      }),
    );

    expect(snapshot.input).toEqual({
      eligible_trade_in_credit_minor: "0",
      non_taxable_discounts_minor: "1500",
      non_taxable_fees_minor: "1000",
      taxable_discounts_minor: "50000",
      taxable_fees_minor: "2500",
      trade_in_eligibility: null,
      vehicle_price_minor: "1000000",
    });
    expect(snapshot.output).toEqual({
      eligible_taxable_consideration_minor: "952500",
      gst_minor: "47625",
      net_cash_consideration_before_payments_minor: "1095137",
      non_taxable_fees_minor: "0",
      qst_minor: "95012",
      total_tax_minor: "142637",
    });
  });

  it("permits official selection only for an active exact version with approval evidence", () => {
    const pack = activePack();
    const official = selector({ usage: "official" });
    expect(decideTaxPackAvailability(pack, official)).toMatchObject({
      state: "available_for_official",
      available: true,
      gates: [],
      packChecksum: pack.checksum,
    });
    expect(selectTaxPack([pack], official)).toBe(pack);
  });

  it("adapts an approved exact tax version to the calculation runtime port", () => {
    const pack = activePack();
    const port = createCalculationTaxPort(pack, {
      jurisdiction: "CA-QC",
      usage: "official",
    });
    const result = port.calculate({
      context: "vehicle_retail_sale",
      inputs: {
        transaction_date: "2026-07-15",
        currency_code: "CAD",
        eligible_taxable_consideration_minor: "1000",
      },
    });
    expect(result.outputs).toMatchObject({
      gst_minor: "50",
      qst_minor: "100",
      total_tax_minor: "150",
    });
    expect(result).toMatchObject({
      packKey: "tax-ca-qc",
      packVersion: "1.0.0",
      packChecksum: pack.checksum,
    });
    expect(result.snapshotChecksum).toMatch(/^[0-9a-f]{64}$/u);
  });
});

describe("T-TAX-002 unavailable and unsupported tax decisions fail closed", () => {
  it("blocks draft, missing, expired, mismatched, retired, and ambiguous official packs", () => {
    const draft = compileTaxPack(CANDIDATE_PACK);
    const draftOfficial = selector({ usage: "official" });
    expect(decideTaxPackAvailability(draft, draftOfficial)).toMatchObject({
      state: "unavailable",
      available: false,
      gates: ["pack_not_active", "approval_missing"],
    });
    expect(taxCode(() => selectTaxPack([draft], draftOfficial))).toBe(
      "tax_pack_unavailable",
    );
    expect(taxCode(() => selectTaxPack([], draftOfficial))).toBe(
      "tax_pack_unavailable",
    );

    const active = activePack();
    const expired = compileTaxPack(
      candidatePack({
        activation_status: "active",
        approval_refs: ["professional-review:synthetic"],
        effective_to: "2026-07-15",
      }),
    );
    expect(
      taxCode(() =>
        selectTaxPack(
          [expired],
          selector({ usage: "official", transactionDate: "2026-07-16" }),
        ),
      ),
    ).toBe("tax_pack_unavailable");
    for (const mismatch of [
      selector({ usage: "official", transactionDate: "2026-07-14" }),
      selector({ usage: "official", jurisdiction: "CA-ON" }),
      selector({ usage: "official", context: "property_sale" }),
      selector({ usage: "official", currency: "USD" }),
    ]) {
      expect(taxCode(() => selectTaxPack([active], mismatch))).toBe(
        "tax_pack_unavailable",
      );
    }

    const retired = compileTaxPack(
      candidatePack({ activation_status: "retired" }),
    );
    expect(taxCode(() => selectTaxPack([retired], selector()))).toBe(
      "tax_pack_unavailable",
    );
    expect(
      taxCode(() =>
        selectTaxPack(
          [active, activePack("tax-ca-qc-second")],
          selector({ usage: "official" }),
        ),
      ),
    ).toBe("ambiguous_tax_pack");
  });

  it("prohibits address inference by enforcing the selector discriminator exactly", () => {
    const withAddress = {
      ...selector(),
      address: "123 Example Street, Example City",
    } as unknown as TaxPackSelector;
    expect(
      taxCode(() =>
        selectTaxPack([compileTaxPack(CANDIDATE_PACK)], withAddress),
      ),
    ).toBe("invalid_input");
  });

  it("rejects packs whose approval, source, rule, or rounding claims are unsafe", () => {
    expect(
      taxCode(() =>
        compileTaxPack(
          candidatePack({ activation_status: "active", approval_refs: [] }),
        ),
      ),
    ).toBe("invalid_pack");
    expect(
      taxCode(() =>
        compileTaxPack(candidatePack({ effective_to: "2026-07-14" })),
      ),
    ).toBe("invalid_pack");
    expect(
      taxCode(() =>
        compileTaxPack(
          candidatePack({
            sources: [
              { ...CANDIDATE_PACK.sources[0], url: "http://example.test/tax" },
            ],
          }),
        ),
      ),
    ).toBe("invalid_pack");
    expect(
      taxCode(() =>
        compileTaxPack(
          candidatePack({
            rules: {
              ...CANDIDATE_PACK.rules,
              rounding: {
                ...CANDIDATE_PACK.rules.rounding,
                stage: "after_grand_total",
              },
            },
          }),
        ),
      ),
    ).toBe("invalid_pack");
    expect(
      taxCode(() =>
        compileTaxPack(
          candidatePack({
            rules: {
              ...CANDIDATE_PACK.rules,
              taxes: [
                {
                  ...CANDIDATE_PACK.rules.taxes[0],
                  taxable_base: "unimplemented_base",
                },
              ],
            },
          }),
        ),
      ),
    ).toBe("invalid_pack");
  });

  it("requires explicit trade-in eligibility or a fully authorized override", () => {
    const pack = compileTaxPack(CANDIDATE_PACK);
    const tradeInput = {
      vehicle_price_minor: "1000000",
      eligible_trade_in_credit_minor: "300000",
    } as const;
    expect(
      taxCode(() => executeTaxCalculation(pack, request(tradeInput))),
    ).toBe("trade_in_eligibility_required");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request(tradeInput, {
            override: {
              kind: "trade_in_eligibility",
              permissionKey: "tax.override",
              permissionGranted: false,
              recentStrongAuth: true,
              reason: "Reviewed exception",
              reviewReference: "review-123",
            },
          }),
        ),
      ),
    ).toBe("tax_override_denied");

    const approved = executeTaxCalculation(
      pack,
      request(tradeInput, {
        override: {
          kind: "trade_in_eligibility",
          permissionKey: "tax.override",
          permissionGranted: true,
          recentStrongAuth: true,
          reason: "  Reviewed exception  ",
          reviewReference: "  review-123  ",
        },
      }),
    );
    expect(approved.override).toEqual({
      kind: "trade_in_eligibility",
      permissionKey: "tax.override",
      permissionGranted: true,
      recentStrongAuth: true,
      reason: "Reviewed exception",
      reviewReference: "review-123",
    });
    expect(approved.output.eligible_taxable_consideration_minor).toBe("700000");
  });

  it("rejects loose eligibility, lien-payoff inference, unsupported scenarios, and mixed bases", () => {
    const pack = compileTaxPack(CANDIDATE_PACK);
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "1000",
            eligible_trade_in_credit_minor: "100",
            trade_in_eligibility: {
              explicitly_confirmed: true,
              review_reference: "review-123",
              inferred_from_address: true,
            },
          } as unknown as TaxCalculationRequest["input"]),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "1000",
            trade_in_lien_payoff_minor: "100",
          } as unknown as TaxCalculationRequest["input"]),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "1000",
            scenario: "cross_border_sale",
          }),
        ),
      ),
    ).toBe("unsupported_transaction");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({ vehicle_price_minor: "1000", scenario: "unknown_case" }),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            eligible_taxable_consideration_minor: "1000",
            vehicle_price_minor: "1000",
          }),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            eligible_taxable_consideration_minor: "1000",
            taxable_discounts_minor: "100",
          }),
        ),
      ),
    ).toBe("invalid_input");
  });

  it("rejects unsafe money values and incomplete golden assertions", () => {
    const pack = compileTaxPack(CANDIDATE_PACK);
    expect(
      taxCode(() =>
        executeTaxCalculation(pack, request({ vehicle_price_minor: -1 })),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(pack, request({ vehicle_price_minor: 0.1 })),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "1000",
            taxable_discounts_minor: "-1",
          }),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "1000",
            non_taxable_discounts_minor: {} as unknown as string,
          }),
        ),
      ),
    ).toBe("invalid_input");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({ vehicle_price_minor: "9223372036854775808" }),
        ),
      ),
    ).toBe("numeric_overflow");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({ vehicle_price_minor: "9223372036854775807" }),
        ),
      ),
    ).toBe("numeric_overflow");
    expect(
      taxCode(() =>
        executeTaxCalculation(
          pack,
          request({
            vehicle_price_minor: "9223372036854775807",
            taxable_fees_minor: "1",
            taxable_discounts_minor: "0",
          }),
        ),
      ),
    ).toBe("numeric_overflow");
    expect(
      taxCode(() =>
        runTaxGoldenCases(pack, [{ ...GOLDEN_CASES[0]!, expected: {} }]),
      ),
    ).toBe("invalid_input");
  });
});
