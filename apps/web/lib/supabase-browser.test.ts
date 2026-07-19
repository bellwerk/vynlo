// Stable test IDs: T-TEN-002, T-API-001.
import { describe, expect, it } from "vitest";
import { parsePublicSupabaseConfig } from "./supabase-browser";

const publicKey = "public-anon-key-with-sufficient-length";

describe("public Supabase browser configuration", () => {
  it("M1-AUTH-UI-001 accepts HTTPS and trims a trailing slash", () => {
    expect(
      parsePublicSupabaseConfig("https://example.supabase.co/", publicKey),
    ).toEqual({
      anonKey: publicKey,
      url: "https://example.supabase.co",
    });
  });

  it("M1-AUTH-UI-002 permits HTTP only for a loopback development host", () => {
    expect(
      parsePublicSupabaseConfig("http://127.0.0.1:54321", publicKey).url,
    ).toBe("http://127.0.0.1:54321");
    expect(() =>
      parsePublicSupabaseConfig("http://supabase.example", publicKey),
    ).toThrow(/HTTPS/u);
  });

  it("M1-AUTH-UI-003 fails closed when the public key is absent", () => {
    expect(() =>
      parsePublicSupabaseConfig("https://example.supabase.co", ""),
    ).toThrow(/not configured/u);
  });

  it("M1-AUTH-UI-004 rejects server-only project keys", () => {
    const servicePayload = Buffer.from(
      JSON.stringify({ role: "service_role" }),
    ).toString("base64url");
    expect(() =>
      parsePublicSupabaseConfig(
        "https://example.supabase.co",
        `header.${servicePayload}.signature`,
      ),
    ).toThrow(/not configured/u);
    expect(() =>
      parsePublicSupabaseConfig(
        "https://example.supabase.co",
        "sb_secret_this-value-must-stay-server-only",
      ),
    ).toThrow(/not configured/u);
  });
});
