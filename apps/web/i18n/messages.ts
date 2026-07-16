export const messages = {
  en: {
    brandHome: "Vynlo home",
    navigationLabel: "Primary navigation",
    navigation: ["Overview", "Inventory", "People", "Deals"],
    environment: "Local foundation",
    stage: "Stage 0",
    foundation: "Repository foundation",
    heading: "A calm operating surface for busy dealership teams.",
    introduction:
      "The application shell is ready for tenant-neutral workflows. Product modules remain intentionally inactive until their implementation stages.",
    healthAction: "View system health",
    readinessAction: "Readiness JSON",
    statusLabel: "Foundation status",
    cards: [
      [
        "Tenant-neutral by design",
        "Workspace configuration is data. Platform packages do not depend on tenant seed folders.",
      ],
      [
        "Mobile is primary",
        "This shell starts at 360 pixels with touch-safe navigation and no horizontal overflow.",
      ],
      [
        "Security before features",
        "No production credentials or customer fixtures belong in this repository.",
      ],
    ],
    footer: ["Vynlo foundation", "Build deliberately · verify continuously"],
    healthTitle: "System health",
    operational: "Operational",
    webShell: "Web shell",
    healthy: "Healthy",
    readiness: "Readiness",
    liveness: "Liveness",
    jsonEndpoint: "JSON endpoint",
  },
  fr: {
    brandHome: "Accueil Vynlo",
    navigationLabel: "Navigation principale",
    navigation: ["Vue d’ensemble", "Inventaire", "Personnes", "Dossiers"],
    environment: "Fondation locale",
    stage: "Étape 0",
    foundation: "Fondation du dépôt",
    heading: "Une surface de travail calme pour les équipes de concession.",
    introduction:
      "La structure applicative est prête pour des flux neutres. Les modules produit restent inactifs jusqu’à leur étape de mise en œuvre.",
    healthAction: "Voir l’état du système",
    readinessAction: "État de préparation JSON",
    statusLabel: "État de la fondation",
    cards: [
      [
        "Neutre par conception",
        "La configuration d’un espace de travail est constituée de données. Les paquets de plateforme ne dépendent pas des dossiers d’amorçage.",
      ],
      [
        "Le mobile en premier",
        "Cette structure commence à 360 pixels avec une navigation tactile et sans débordement horizontal.",
      ],
      [
        "La sécurité avant les fonctions",
        "Aucun identifiant de production ni aucune donnée client ne doit entrer dans ce dépôt.",
      ],
    ],
    footer: [
      "Fondation Vynlo",
      "Construire délibérément · vérifier continuellement",
    ],
    healthTitle: "État du système",
    operational: "Opérationnel",
    webShell: "Interface web",
    healthy: "Fonctionnel",
    readiness: "Préparation",
    liveness: "Disponibilité",
    jsonEndpoint: "Point d’accès JSON",
  },
} as const;

export const defaultLocale = "en" as const;
