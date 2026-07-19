export interface VehicleMediaManagerCopy {
  readonly addHeading: string;
  readonly addHint: string;
  readonly archiveAction: string;
  readonly archiveCancel: string;
  readonly archiveConfirm: string;
  readonly archiveHeading: string;
  readonly archiveReasonLabel: string;
  readonly archiveReasonPlaceholder: string;
  readonly archivingStatus: string;
  readonly backAction: string;
  readonly captionLabel: string;
  readonly captionPlaceholder: string;
  readonly conflictError: string;
  readonly countLabel: string;
  readonly coverAction: string;
  readonly coverLabel: string;
  readonly description: string;
  readonly emptyDescription: string;
  readonly emptyHeading: string;
  readonly eyebrow: string;
  readonly failedHint: string;
  readonly genericError: string;
  readonly heading: string;
  readonly loadError: string;
  readonly loading: string;
  readonly moveDownAction: string;
  readonly moveUpAction: string;
  readonly movingStatus: string;
  readonly photoLabel: string;
  readonly refreshAction: string;
  readonly reprocessAction: string;
  readonly reprocessReason: string;
  readonly reprocessingStatus: string;
  readonly retryAction: string;
  readonly saveCaptionAction: string;
  readonly savedStatus: string;
  readonly savingStatus: string;
  readonly settingCoverStatus: string;
  readonly skipToContent: string;
  readonly statusAwaitingUpload: string;
  readonly statusFailed: string;
  readonly statusProcessing: string;
  readonly statusQuarantined: string;
  readonly statusReady: string;
  readonly thumbnailAlt: string;
  readonly thumbnailUnavailable: string;
  readonly transientHint: string;
}

export const vehicleMediaMessages: Readonly<
  Record<"en" | "fr", VehicleMediaManagerCopy>
> = Object.freeze({
  en: {
    addHeading: "Add another photo",
    addHint:
      "New uploads enter quarantine and appear here while processing continues.",
    archiveAction: "Archive photo",
    archiveCancel: "Cancel",
    archiveConfirm: "Confirm archive",
    archiveHeading: "Archive this photo?",
    archiveReasonLabel: "Archive reason",
    archiveReasonPlaceholder: "Why should this photo leave the active set?",
    archivingStatus: "Archiving photo…",
    backAction: "Back to inventory",
    captionLabel: "Caption",
    captionPlaceholder: "Describe this vehicle angle",
    conflictError:
      "The photo set changed. The latest version has been loaded; review and try again.",
    countLabel: "{count} active photos",
    coverAction: "Use as cover",
    coverLabel: "Cover photo",
    description:
      "Review processed photos, choose the cover, set order, and keep retry history visible.",
    emptyDescription:
      "Upload the first vehicle photo below. Processing status will stay visible here.",
    emptyHeading: "No active photos yet",
    eyebrow: "Vehicle media",
    failedHint:
      "Processing stopped after bounded retries. Retry when the source or provider is ready.",
    genericError: "The media operation could not be completed. Try again.",
    heading: "Photo order & status",
    loadError: "Photos could not be loaded.",
    loading: "Loading vehicle photos…",
    moveDownAction: "Move photo down",
    moveUpAction: "Move photo up",
    movingStatus: "Saving photo order…",
    photoLabel: "Photo {position}",
    refreshAction: "Refresh status",
    reprocessAction: "Retry processing",
    reprocessReason: "Operator retry from the vehicle media manager",
    reprocessingStatus: "Queueing a durable processing retry…",
    retryAction: "Try again",
    saveCaptionAction: "Save caption",
    savedStatus: "Saved",
    savingStatus: "Saving caption…",
    settingCoverStatus: "Updating cover photo…",
    skipToContent: "Skip to vehicle media",
    statusAwaitingUpload: "Awaiting upload",
    statusFailed: "Processing failed",
    statusProcessing: "Processing",
    statusQuarantined: "Verified in quarantine",
    statusReady: "Ready",
    thumbnailAlt: "Vehicle photo {position}{caption}",
    thumbnailUnavailable: "Processed thumbnail not available yet",
    transientHint:
      "Processing continues in the background. This view refreshes automatically.",
  },
  fr: {
    addHeading: "Ajouter une autre photo",
    addHint:
      "Les nouveaux téléversements passent en quarantaine et s’affichent ici pendant le traitement.",
    archiveAction: "Archiver la photo",
    archiveCancel: "Annuler",
    archiveConfirm: "Confirmer l’archivage",
    archiveHeading: "Archiver cette photo?",
    archiveReasonLabel: "Motif d’archivage",
    archiveReasonPlaceholder:
      "Pourquoi retirer cette photo de l’ensemble actif?",
    archivingStatus: "Archivage de la photo…",
    backAction: "Retour à l’inventaire",
    captionLabel: "Légende",
    captionPlaceholder: "Décrire cet angle du véhicule",
    conflictError:
      "L’ensemble de photos a changé. La version la plus récente est chargée; vérifiez-la et réessayez.",
    countLabel: "{count} photos actives",
    coverAction: "Utiliser comme couverture",
    coverLabel: "Photo de couverture",
    description:
      "Vérifiez les photos traitées, choisissez la couverture, définissez l’ordre et gardez les reprises visibles.",
    emptyDescription:
      "Téléversez la première photo du véhicule ci-dessous. Son état de traitement restera visible ici.",
    emptyHeading: "Aucune photo active",
    eyebrow: "Médias du véhicule",
    failedHint:
      "Le traitement s’est arrêté après les reprises limitées. Réessayez lorsque la source ou le fournisseur est prêt.",
    genericError:
      "L’opération sur le média n’a pas pu être terminée. Réessayez.",
    heading: "Ordre et état des photos",
    loadError: "Impossible de charger les photos.",
    loading: "Chargement des photos du véhicule…",
    moveDownAction: "Déplacer la photo vers le bas",
    moveUpAction: "Déplacer la photo vers le haut",
    movingStatus: "Enregistrement de l’ordre…",
    photoLabel: "Photo {position}",
    refreshAction: "Actualiser l’état",
    reprocessAction: "Relancer le traitement",
    reprocessReason:
      "Relance par un opérateur depuis le gestionnaire de médias du véhicule",
    reprocessingStatus: "Mise en file d’une reprise durable…",
    retryAction: "Réessayer",
    saveCaptionAction: "Enregistrer la légende",
    savedStatus: "Enregistré",
    savingStatus: "Enregistrement de la légende…",
    settingCoverStatus: "Mise à jour de la couverture…",
    skipToContent: "Passer aux médias du véhicule",
    statusAwaitingUpload: "En attente du téléversement",
    statusFailed: "Échec du traitement",
    statusProcessing: "Traitement en cours",
    statusQuarantined: "Vérifié en quarantaine",
    statusReady: "Prête",
    thumbnailAlt: "Photo du véhicule {position}{caption}",
    thumbnailUnavailable: "La miniature traitée n’est pas encore disponible",
    transientHint:
      "Le traitement se poursuit en arrière-plan. Cette vue s’actualise automatiquement.",
  },
});
