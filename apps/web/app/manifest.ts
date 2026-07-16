import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    background_color: "#f4f1e8",
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
    theme_color: "#17251f",
  };
}
