"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export interface PublicSupabaseConfig {
  readonly anonKey: string;
  readonly url: string;
}

let browserClient: SupabaseClient | undefined;

function isLocalHostname(hostname: string): boolean {
  return ["127.0.0.1", "localhost", "::1"].includes(hostname);
}

function parseLegacyJwtRole(key: string): string | null {
  const parts = key.split(".");
  if (parts.length !== 3 || !parts[1]) {
    return null;
  }
  try {
    const base64 = parts[1].replace(/-/gu, "+").replace(/_/gu, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const payload: unknown = JSON.parse(atob(padded));
    return typeof payload === "object" &&
      payload !== null &&
      "role" in payload &&
      typeof payload.role === "string"
      ? payload.role
      : null;
  } catch {
    return null;
  }
}

export function parsePublicSupabaseConfig(
  urlValue: string | undefined,
  keyValue: string | undefined,
): PublicSupabaseConfig {
  const url = new URL(urlValue?.trim() ?? "");
  const isSafeProtocol =
    url.protocol === "https:" ||
    (url.protocol === "http:" && isLocalHostname(url.hostname));

  if (!isSafeProtocol) {
    throw new TypeError("Supabase must use HTTPS except in local development.");
  }

  const anonKey = keyValue?.trim() ?? "";
  const legacyRole = parseLegacyJwtRole(anonKey);
  if (
    anonKey.length < 20 ||
    anonKey.startsWith("sb_secret_") ||
    (legacyRole !== null && legacyRole !== "anon")
  ) {
    throw new TypeError("The public Supabase key is not configured.");
  }

  return Object.freeze({
    anonKey,
    url: url.toString().replace(/\/$/u, ""),
  });
}

export function getBrowserSupabase(): SupabaseClient {
  if (browserClient) {
    return browserClient;
  }

  const config = parsePublicSupabaseConfig(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );
  browserClient = createClient(config.url, config.anonKey, {
    auth: {
      autoRefreshToken: true,
      detectSessionInUrl: true,
      persistSession: true,
    },
  });
  return browserClient;
}
