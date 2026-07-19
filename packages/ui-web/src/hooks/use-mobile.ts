"use client";

import * as React from "react";

export const MOBILE_BREAKPOINT = 768;

function subscribeToMobileViewport(onStoreChange: () => void): () => void {
  const mediaQuery = window.matchMedia(
    `(max-width: ${MOBILE_BREAKPOINT - 1}px)`,
  );
  mediaQuery.addEventListener("change", onStoreChange);
  return () => mediaQuery.removeEventListener("change", onStoreChange);
}

function getMobileSnapshot(): boolean {
  return window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`).matches;
}

function getServerMobileSnapshot(): boolean {
  return false;
}

/** Hydration-safe viewport capability used by the responsive shadcn sidebar. */
export function useIsMobile(): boolean {
  return React.useSyncExternalStore(
    subscribeToMobileViewport,
    getMobileSnapshot,
    getServerMobileSnapshot,
  );
}
