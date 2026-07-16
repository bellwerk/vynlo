"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import {
  localeCookieName,
  resolveLocale,
  sanitizeReturnPath,
} from "../../i18n/locale";

export async function setLocale(formData: FormData): Promise<never> {
  const locale = resolveLocale(formData.get("locale"));
  const returnTo = sanitizeReturnPath(formData.get("returnTo"));
  const cookieStore = await cookies();

  cookieStore.set(localeCookieName, locale, {
    httpOnly: true,
    maxAge: 60 * 60 * 24 * 365,
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });

  redirect(returnTo);
}
