import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    background_color: "#f4f1e8",
    description: "Mobile-first dealership operations platform",
    display: "standalone",
    name: "Vynlo",
    scope: "/",
    short_name: "Vynlo",
    start_url: "/",
    theme_color: "#17251f",
  };
}
