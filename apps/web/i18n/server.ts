import { cookies } from "next/headers";
import { localeCookieName, resolveLocale } from "./locale";
import type { Locale } from "./messages";

export async function getRequestLocale(): Promise<Locale> {
  const cookieStore = await cookies();
  return resolveLocale(cookieStore.get(localeCookieName)?.value);
}
