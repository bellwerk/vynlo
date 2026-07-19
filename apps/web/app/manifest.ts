import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    // The Web App Manifest standard accepts one color, not media-qualified
    // light/dark values. Keep the light system background as the install and
    // launch fallback; app/layout.tsx supplies media-qualified theme-color
    // meta tags so browser chrome follows both operating-system modes.
    background_color: "#F5F5F7",
    categories: ["business", "productivity"],
    description: "Mobile-first dealership operations platform",
    display: "standalone",
    icons: [
      {
        sizes: "192x192",
        src: "/icons/vynlo-192.svg",
        type: "image/svg+xml",
      },
      {
        purpose: "maskable",
        sizes: "512x512",
        src: "/icons/vynlo-512.svg",
        type: "image/svg+xml",
      },
    ],
    id: "/",
    name: "Vynlo",
    orientation: "any",
    scope: "/",
    short_name: "Vynlo",
    start_url: "/",
    theme_color: "#F5F5F7",
  };
}
