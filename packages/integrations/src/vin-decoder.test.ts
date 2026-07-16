import { describe, expect, it, vi } from "vitest";

import { NhtsaVpicVinDecoderAdapter, VinDecoderError } from "./vin-decoder";

const vin = "1HGCM82633A004352";
const now = new Date("2026-07-16T12:00:00.000Z");

function response(
  body: unknown,
  init: Readonly<{ headers?: HeadersInit; status?: number }> = {},
): Response {
  return Response.json(body, init);
}

function decodedPayload() {
  return {
    Count: 1,
    Message: "Results returned successfully",
    Results: [
      {
        BodyClass: "Sedan/Saloon",
        DisplacementL: "2.4",
        DriveType: "4x2",
        EngineCylinders: "4",
        EngineHP: "160",
        ErrorCode: "0",
        ErrorText:
          "0 - VIN decoded clean. Check Digit (9th position) is correct",
        FuelTypePrimary: "Gasoline",
        Make: "HONDA",
        Model: "Accord",
        ModelYear: "2003",
        TransmissionStyle: "Automatic",
        Trim: "EX-V6",
      },
    ],
    SearchCriteria: `VIN(s): ${vin}`,
  };
}

describe("T-INV-002 / T-JOB-003 NhtsaVpicVinDecoderAdapter", () => {
  it("normalizes VIN input, sends a bounded HTTPS request, and maps suggestions", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      response(decodedPayload()),
    );
    const adapter = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation,
      now: () => now,
      providerVersion: "vpic-4.06",
    });

    await expect(
      adapter.decode({ modelYear: 2003, vin: ` ${vin.toLowerCase()} ` }),
    ).resolves.toEqual({
      decodedAt: now.toISOString(),
      facts: {
        bodyType: "Sedan/Saloon",
        cylinders: 4,
        drivetrain: "4x2",
        engineLiters: "2.4",
        fuelType: "Gasoline",
        horsepower: 160,
        make: "HONDA",
        model: "Accord",
        modelYear: 2003,
        transmission: "Automatic",
        trim: "EX-V6",
      },
      providerKey: "nhtsa_vpic",
      providerVersion: "vpic-4.06",
      rawResponse: decodedPayload(),
      vin,
      warnings: [
        "0 - VIN decoded clean. Check Digit (9th position) is correct",
      ],
    });

    const [requestedUrl, init] = fetchImplementation.mock.calls[0] ?? [];
    expect(String(requestedUrl)).toBe(
      `https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/${vin}?format=json&modelyear=2003`,
    );
    expect(init).toMatchObject({ method: "GET", redirect: "error" });
    expect(new Headers(init?.headers).get("accept")).toBe("application/json");
  });

  it.each(["short", "1HGCM82633A00I352", "1HGCM82633A00Q352"])(
    "rejects invalid VIN %s without provider traffic",
    async (invalidVin) => {
      const fetchImplementation = vi.fn<typeof fetch>();
      const adapter = new NhtsaVpicVinDecoderAdapter({ fetchImplementation });

      await expect(adapter.decode({ vin: invalidVin })).rejects.toMatchObject({
        code: "invalid_vin",
        retryable: false,
      });
      expect(fetchImplementation).not.toHaveBeenCalled();
    },
  );

  it("normalizes missing and non-numeric provider facts to null", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async () =>
      response({
        Results: [
          {
            DisplacementL: "Not Applicable",
            EngineCylinders: "2.5",
            ErrorCode: "6,7",
            ErrorText: "Incomplete vehicle data",
            Make: " ",
            Model: "Example",
          },
        ],
      }),
    );
    const result = await new NhtsaVpicVinDecoderAdapter({
      fetchImplementation,
    }).decode({ vin });

    expect(result.facts).toMatchObject({
      cylinders: null,
      engineLiters: null,
      make: null,
      model: "Example",
    });
    expect(result.warnings).toEqual([
      "vpic_error_code:6,7",
      "Incomplete vehicle data",
    ]);
  });

  it("surfaces rate limits with retry hints and retry-safe classification", async () => {
    const adapter = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation: vi.fn(async () =>
        response(
          { error: "rate limited" },
          { headers: { "Retry-After": "17" }, status: 429 },
        ),
      ),
      now: () => now,
    });

    await expect(adapter.decode({ vin })).rejects.toMatchObject({
      code: "provider_rate_limited",
      retryAfterMs: 17_000,
      retryable: true,
    });
  });

  it("caps provider retry hints at the durable job boundary", async () => {
    const adapter = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation: vi.fn(async () =>
        response(
          { error: "rate limited" },
          { headers: { "Retry-After": "999999999999999999999" }, status: 429 },
        ),
      ),
      now: () => now,
    });

    await expect(adapter.decode({ vin })).rejects.toMatchObject({
      code: "provider_rate_limited",
      retryAfterMs: 86_400_000,
      retryable: true,
    });
  });

  it.each([
    [503, "provider_unavailable", true],
    [422, "provider_rejected", false],
  ] as const)(
    "classifies HTTP %s without leaking the response body",
    async (status, code, retryable) => {
      const adapter = new NhtsaVpicVinDecoderAdapter({
        fetchImplementation: vi.fn(async () =>
          response({ secret: "must-not-leak" }, { status }),
        ),
      });

      const error = await adapter
        .decode({ vin })
        .catch((cause: unknown) => cause);
      expect(error).toBeInstanceOf(VinDecoderError);
      expect(error).toMatchObject({ code, retryable });
      expect(String(error)).not.toContain("must-not-leak");
    },
  );

  it("rejects malformed and oversized provider responses", async () => {
    const invalid = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation: vi.fn(
        async () =>
          new Response("not-json", {
            headers: { "Content-Type": "application/json" },
          }),
      ),
    });
    await expect(invalid.decode({ vin })).rejects.toMatchObject({
      code: "provider_response_invalid",
      retryable: false,
    });

    const oversized = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation: vi.fn(
        async () => new Response("{}", { headers: { "Content-Length": "51" } }),
      ),
      maxResponseBytes: 50,
    });
    await expect(oversized.decode({ vin })).rejects.toMatchObject({
      code: "provider_response_too_large",
      retryable: false,
    });

    const chunkedOversized = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation: vi.fn(
        async () =>
          new Response(
            new ReadableStream<Uint8Array>({
              start(controller) {
                controller.enqueue(new Uint8Array(30));
                controller.enqueue(new Uint8Array(30));
                controller.close();
              },
            }),
          ),
      ),
      maxResponseBytes: 50,
    });
    await expect(chunkedOversized.decode({ vin })).rejects.toMatchObject({
      code: "provider_response_too_large",
      retryable: false,
    });
  });

  it("distinguishes caller cancellation from a retryable provider timeout", async () => {
    const caller = new AbortController();
    const fetchImplementation = vi.fn<typeof fetch>(
      (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException("Aborted", "AbortError")),
          );
        }),
    );
    const adapter = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation,
      timeoutMs: 10_000,
    });
    const request = adapter.decode({ signal: caller.signal, vin });
    caller.abort("navigation");
    await expect(request).rejects.toMatchObject({
      code: "provider_aborted",
      retryable: false,
    });

    const timeoutAdapter = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation,
      timeoutMs: 1,
    });
    await expect(timeoutAdapter.decode({ vin })).rejects.toMatchObject({
      code: "provider_unavailable",
      retryable: true,
    });
  });

  it("keeps caller cancellation and timeout active while consuming the body", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(
      async (_input, init) =>
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              init?.signal?.addEventListener(
                "abort",
                () =>
                  controller.error(new DOMException("Aborted", "AbortError")),
                { once: true },
              );
            },
          }),
        ),
    );
    const caller = new AbortController();
    const request = new NhtsaVpicVinDecoderAdapter({
      fetchImplementation,
      timeoutMs: 10_000,
    }).decode({ signal: caller.signal, vin });
    caller.abort("navigation");
    await expect(request).rejects.toMatchObject({
      code: "provider_aborted",
      retryable: false,
    });

    await expect(
      new NhtsaVpicVinDecoderAdapter({
        fetchImplementation,
        timeoutMs: 1,
      }).decode({ vin }),
    ).rejects.toMatchObject({
      code: "provider_unavailable",
      retryable: true,
    });
  });

  it("rejects unsafe provider endpoint configuration", () => {
    expect(
      () =>
        new NhtsaVpicVinDecoderAdapter({
          endpoint: "http://example.invalid/decoder",
        }),
    ).toThrow(/HTTPS URL/u);
    expect(
      () =>
        new NhtsaVpicVinDecoderAdapter({
          endpoint: "https://user:secret@example.invalid/decoder",
        }),
    ).toThrow(/without credentials/u);
  });
});
