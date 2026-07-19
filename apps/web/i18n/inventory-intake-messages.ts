export const inventoryIntakeMessages = {
  en: {
    openDuplicateBlocked:
      "The duplicate review did not approve this intake. Reload the current VIN state before continuing.",
    acquisitionDateLabel: "Acquisition date",
    activeStatus: "Active",
    archivedStatus: "Archived",
    backAction: "Back to inventory",
    bodyTypeLabel: "Body type",
    brandHome: "Vynlo home",
    cancelledStatus: "Cancelled",
    candidateHistorical: "Historical inventory",
    candidateOpen: "Open inventory",
    candidateVehicle: "Existing vehicle",
    closedStatus: "Closed",
    conditionLabel: "Vehicle condition",
    confirmDetailsAction: "Confirm vehicle details",
    consumedStatus: "Manual intake completed",
    createAction: "Allocate stock and add inventory",
    createdDescription: "Stock {stock} is ready in the workspace inventory.",
    createdHeading: "Inventory added",
    creating: "Allocating stock…",
    linkedDescription:
      "This VIN request is linked to existing stock {stock}; no new stock number was allocated.",
    linkedHeading: "Existing inventory linked",
    linkingOpenInventory: "Linking existing stock…",
    linkInventoryDescription:
      "Confirm the existing unit’s active location and condition. The stock definition is validated, but no number is allocated; acquisition, odometer, price, and notes remain unchanged.",
    linkOpenInventoryAction: "Link request to existing stock",
    currencyLabel: "Currency",
    cylindersLabel: "Cylinders",
    deadLetterStatus: "Decode failed",
    decodeDescription:
      "VIN decoding runs as a durable job. Confirm every mapped value before continuing.",
    decodeHeading: "Decode and confirm",
    decisionLabel: "Review decision",
    developmentPreview: "Development preview · synthetic intake",
    drivetrainLabel: "Drivetrain",
    draftStatus: "Draft",
    duplicateDescription:
      "Review the existing workspace record before any stock number is allocated.",
    duplicateHeading: "Duplicate VIN review required",
    engineLabel: "Engine",
    errorDescription:
      "The request could not be completed. Your entered values are preserved.",
    errorHeading: "Action unavailable",
    fieldRequired: "Complete the required fields before continuing.",
    fuelTypeLabel: "Fuel type",
    heading: "Add inventory",
    horsepowerLabel: "Horsepower",
    introduction:
      "Decode the VIN, review possible duplicates, then allocate stock from an active definition.",
    jobAttempt: "Attempt {attempt} of {maximum}",
    localeLabel: "Language",
    localeNames: { en: "English", fr: "Français" },
    locationLabel: "Inventory location",
    makeLabel: "Make",
    manualConfirmationLabel:
      "I confirm these facts were checked against the vehicle paperwork and should be used for an audited manual intake.",
    manualContinueAction: "Confirm manual facts and continue",
    manualCreateAction: "Create audited manual inventory",
    manualDescription:
      "The provider exhausted its durable attempts. You may retain retry or enter verified facts from the vehicle paperwork; this path is audited and remains linked to the failed request.",
    manualDuplicateDecisionLabel: "Existing vehicle relationship (optional)",
    manualDuplicateLegend: "Duplicate relationship",
    manualDuplicateNone: "Create a new vehicle identity",
    manualDuplicateReasonLabel: "Relationship reason",
    manualHeading: "Continue with audited manual facts",
    manualInventoryDescription:
      "Choose active workspace configuration before the audited manual intake allocates stock and links this inventory to the terminal VIN request.",
    manualReasonLabel: "Why manual facts are required",
    modelLabel: "Model",
    modelYearHintLabel: "Model year hint (optional)",
    modelYearLabel: "Model year",
    navigationLabel: "Inventory intake navigation",
    noStockDefinition:
      "No active stock-number definition is available in this workspace.",
    noActiveLocation:
      "No active inventory location is available in this workspace.",
    noConditionDefinition:
      "No active vehicle-condition definition is available in this workspace.",
    notesLabel: "Public notes (optional)",
    odometerLabel: "Odometer (optional)",
    overrideDecision: "Override an open duplicate (recent MFA required)",
    pendingStatus: "Pending",
    photoChecksumLabel: "SHA-256 checksum",
    photoChooseAction: "Choose a vehicle photo",
    photoChooseAnotherAction: "Choose another photo",
    photoDescription:
      "The original uploads to a private quarantine path, then a durable job verifies and processes it.",
    photoDropHint: "Choose the first marketing photo for this vehicle.",
    photoDurableHint:
      "Verification is queued. You can leave this page while the durable worker scans and processes the photo.",
    photoEmptyError: "Choose a non-empty photo file.",
    photoEyebrow: "Next step · optional",
    photoHashReady: "Hash ready",
    photoHashStage: "Checksum",
    photoHashing: "Computing SHA-256 checksum…",
    photoHeading: "Add vehicle photos",
    photoJobCancelledStatus: "Cancelled",
    photoJobDeadLetterStatus: "Verification failed",
    photoJobLabel: "Verification job",
    photoJobQueuedStatus: "Queued",
    photoJobRetryWaitStatus: "Waiting to retry",
    photoJobRunningStatus: "Verification in progress",
    photoJobSucceededStatus: "Verified",
    photoPolicy: "JPEG, PNG, WebP, HEIC or HEIF · maximum 20 MB",
    photoPreparingUpload: "Preparing a private upload…",
    photoQueueingVerification: "Queueing durable verification…",
    photoRequestError:
      "The private upload request could not be prepared. Your photo remains selected.",
    photoRetryAction: "Retry safely",
    photoRetryReasonLabel: "Reason for retry",
    photoRetryReasonPlaceholder:
      "Confirm why verification should run again (required)",
    photoRetryReasonRequired: "Enter a reason before retrying verification.",
    photoRetryVerificationAction: "Retry verification",
    photoSizeError: "The photo must be 20 MB or smaller.",
    photoStartNewUploadAction: "Start a new upload",
    photoStatusChecking: "Checking private verification status…",
    photoStatusCompleted: "Photo verified and queued for processing.",
    photoStatusDeadLetter:
      "Verification stopped after its retry limit. Review it before retrying.",
    photoStatusError:
      "Verification status is temporarily unavailable. We will check again.",
    photoStatusQueued: "Private verification is queued.",
    photoStatusRejected:
      "This photo was rejected. Choose the correct file and start a new upload.",
    photoStatusRetryWait: "Verification will retry automatically.",
    photoStatusRunning: "Private verification is running.",
    photoStagesLabel: "Photo upload status",
    photoTypeError: "Choose a JPEG, PNG, WebP, HEIC or HEIF photo.",
    photoUploadComplete: "Private upload complete",
    photoUploadError:
      "The private upload was interrupted. Retry continues with the same upload intent.",
    photoUploadInterrupted: "Photo upload interrupted",
    photoUploadProgressLabel: "Vehicle photo upload progress",
    photoUploadStage: "Private upload",
    photoUploading: "Uploading · {progress}%",
    photoVerificationQueued: "Verification queued",
    photoVerificationStage: "Verification",
    photoWaiting: "Waiting",
    priceLabel: "Advertised price (optional)",
    progressLabel: "Step {current} of 3",
    queuedStatus: "Decode queued",
    reacquireDecision: "Reacquire historical inventory",
    retryAction: "Retry decode",
    retryDescription:
      "Record why the durable VIN job should be attempted again.",
    retryHeading: "Retry available",
    retryReasonLabel: "Retry reason",
    retryWaitStatus: "Waiting to retry",
    reuseDecision: "Reuse the existing vehicle",
    reviewAction: "Record duplicate review",
    reviewReasonLabel: "Review reason",
    reviewedStatus: "Duplicate review recorded",
    openDuplicateReviewedStatus:
      "Open duplicate approved for a controlled link to the existing stock record.",
    reviewing: "Recording review…",
    runningStatus: "Decode in progress",
    skipToContent: "Skip to inventory intake",
    startDecodeAction: "Start VIN decode",
    startingDecode: "Starting decode…",
    stepDecode: "Decode and review",
    stepDetails: "Inventory details",
    stepVin: "VIN",
    stockDefinitionLabel: "Active stock definition",
    stockLabel: "Stock",
    succeededStatus: "Decode complete",
    suggestionsDescription:
      "These provider suggestions remain editable until you explicitly confirm them.",
    suggestionsHeading: "Vehicle suggestions",
    transmissionLabel: "Transmission",
    trimLabel: "Trim",
    unavailableValue: "Not provided",
    vehicleDetailsDescription:
      "Workspace defaults are applied. Stock is allocated only when you submit this final step.",
    vehicleDetailsHeading: "Inventory details",
    viewInventoryAction: "View inventory",
    vinHint:
      "Type or paste the 17-character VIN. Camera scanning is not supported.",
    vinLabel: "VIN",
    warningsHeading: "Decoder notes",
    workspaceLabel: "Workspace",
    workspaceLoading: "Loading workspace…",
  },
  fr: {
    openDuplicateBlocked:
      "La révision du doublon n’a pas approuvé cette entrée. Rechargez l’état actuel du NIV avant de continuer.",
    acquisitionDateLabel: "Date d’acquisition",
    activeStatus: "Actif",
    archivedStatus: "Archivé",
    backAction: "Retour à l’inventaire",
    bodyTypeLabel: "Type de carrosserie",
    brandHome: "Accueil Vynlo",
    cancelledStatus: "Annulé",
    candidateHistorical: "Inventaire historique",
    candidateOpen: "Inventaire ouvert",
    candidateVehicle: "Véhicule existant",
    closedStatus: "Fermé",
    conditionLabel: "État du véhicule",
    confirmDetailsAction: "Confirmer les détails du véhicule",
    consumedStatus: "Entrée manuelle terminée",
    createAction: "Attribuer le stock et ajouter le véhicule",
    createdDescription:
      "Le stock {stock} est prêt dans l’inventaire de l’espace.",
    createdHeading: "Véhicule ajouté",
    creating: "Attribution du stock…",
    linkedDescription:
      "Cette demande de NIV est liée au stock existant {stock}; aucun nouveau numéro de stock n’a été attribué.",
    linkedHeading: "Inventaire existant lié",
    linkingOpenInventory: "Liaison au stock existant…",
    linkInventoryDescription:
      "Confirmez l’emplacement actif et l’état du véhicule existant. La définition de stock est validée, mais aucun numéro n’est attribué; l’acquisition, l’odomètre, le prix et les notes restent inchangés.",
    linkOpenInventoryAction: "Lier la demande au stock existant",
    currencyLabel: "Devise",
    cylindersLabel: "Cylindres",
    deadLetterStatus: "Échec du décodage",
    decodeDescription:
      "Le décodage du NIV est une tâche durable. Confirmez chaque valeur avant de continuer.",
    decodeHeading: "Décoder et confirmer",
    decisionLabel: "Décision de révision",
    developmentPreview: "Aperçu de développement · entrée synthétique",
    drivetrainLabel: "Rouage",
    draftStatus: "Brouillon",
    duplicateDescription:
      "Vérifiez le dossier existant avant l’attribution d’un numéro de stock.",
    duplicateHeading: "Révision du NIV en double requise",
    engineLabel: "Moteur",
    errorDescription:
      "La demande n’a pas pu être terminée. Les valeurs saisies sont conservées.",
    errorHeading: "Action indisponible",
    fieldRequired: "Remplissez les champs requis avant de continuer.",
    fuelTypeLabel: "Type de carburant",
    heading: "Ajouter à l’inventaire",
    horsepowerLabel: "Puissance (ch)",
    introduction:
      "Décodez le NIV, révisez les doublons possibles, puis attribuez le stock avec une définition active.",
    jobAttempt: "Tentative {attempt} sur {maximum}",
    localeLabel: "Langue",
    localeNames: { en: "English", fr: "Français" },
    locationLabel: "Emplacement d’inventaire",
    makeLabel: "Marque",
    manualConfirmationLabel:
      "Je confirme que ces faits ont été vérifiés avec les documents du véhicule et doivent servir à une entrée manuelle auditée.",
    manualContinueAction: "Confirmer les faits manuels et continuer",
    manualCreateAction: "Créer l’inventaire manuel audité",
    manualDescription:
      "Le fournisseur a épuisé ses tentatives durables. Vous pouvez conserver la nouvelle tentative ou saisir les faits vérifiés dans les documents du véhicule; ce parcours est audité et lié à la demande échouée.",
    manualDuplicateDecisionLabel: "Lien avec un véhicule existant (facultatif)",
    manualDuplicateLegend: "Lien de doublon",
    manualDuplicateNone: "Créer une nouvelle identité de véhicule",
    manualDuplicateReasonLabel: "Motif du lien",
    manualHeading: "Continuer avec des faits manuels audités",
    manualInventoryDescription:
      "Choisissez la configuration active de l’espace avant que l’entrée manuelle auditée attribue le stock et lie cet inventaire à la demande de NIV terminale.",
    manualReasonLabel: "Pourquoi les faits manuels sont requis",
    modelLabel: "Modèle",
    modelYearHintLabel: "Année modèle estimée (facultatif)",
    modelYearLabel: "Année modèle",
    navigationLabel: "Navigation de l’entrée d’inventaire",
    noStockDefinition:
      "Aucune définition active de numéro de stock n’est disponible dans cet espace.",
    noActiveLocation:
      "Aucun emplacement d’inventaire actif n’est disponible dans cet espace.",
    noConditionDefinition:
      "Aucune définition active de l’état du véhicule n’est disponible dans cet espace.",
    notesLabel: "Notes publiques (facultatif)",
    odometerLabel: "Odomètre (facultatif)",
    overrideDecision: "Autoriser un doublon ouvert (AMF récente requise)",
    pendingStatus: "En attente",
    photoChecksumLabel: "Somme de contrôle SHA-256",
    photoChooseAction: "Choisir une photo du véhicule",
    photoChooseAnotherAction: "Choisir une autre photo",
    photoDescription:
      "L’original est téléversé dans une zone de quarantaine privée, puis une tâche durable le vérifie et le traite.",
    photoDropHint: "Choisissez la première photo marketing de ce véhicule.",
    photoDurableHint:
      "La vérification est en file. Vous pouvez quitter cette page pendant que la tâche durable analyse et traite la photo.",
    photoEmptyError: "Choisissez un fichier photo non vide.",
    photoEyebrow: "Prochaine étape · facultative",
    photoHashReady: "Empreinte prête",
    photoHashStage: "Somme de contrôle",
    photoHashing: "Calcul de la somme SHA-256…",
    photoHeading: "Ajouter des photos du véhicule",
    photoJobCancelledStatus: "Annulée",
    photoJobDeadLetterStatus: "Échec de la vérification",
    photoJobLabel: "Tâche de vérification",
    photoJobQueuedStatus: "En file d’attente",
    photoJobRetryWaitStatus: "En attente d’une nouvelle tentative",
    photoJobRunningStatus: "Vérification en cours",
    photoJobSucceededStatus: "Vérifiée",
    photoPolicy: "JPEG, PNG, WebP, HEIC ou HEIF · maximum 20 Mo",
    photoPreparingUpload: "Préparation du téléversement privé…",
    photoQueueingVerification: "Mise en file de la vérification durable…",
    photoRequestError:
      "La demande de téléversement privé n’a pas pu être préparée. Votre photo reste sélectionnée.",
    photoRetryAction: "Réessayer en toute sécurité",
    photoRetryReasonLabel: "Motif de la nouvelle tentative",
    photoRetryReasonPlaceholder:
      "Confirmez pourquoi la vérification doit recommencer (obligatoire)",
    photoRetryReasonRequired:
      "Saisissez un motif avant de relancer la vérification.",
    photoRetryVerificationAction: "Relancer la vérification",
    photoSizeError: "La photo doit faire 20 Mo ou moins.",
    photoStartNewUploadAction: "Commencer un nouveau téléversement",
    photoStatusChecking: "Vérification de l’état privé en cours…",
    photoStatusCompleted: "Photo vérifiée et mise en file pour traitement.",
    photoStatusDeadLetter:
      "La vérification s’est arrêtée après la limite de tentatives. Examinez-la avant de la relancer.",
    photoStatusError:
      "L’état de la vérification est temporairement indisponible. Nous réessaierons.",
    photoStatusQueued: "La vérification privée est en file.",
    photoStatusRejected:
      "Cette photo a été rejetée. Choisissez le bon fichier et commencez un nouveau téléversement.",
    photoStatusRetryWait: "La vérification sera relancée automatiquement.",
    photoStatusRunning: "La vérification privée est en cours.",
    photoStagesLabel: "État du téléversement de la photo",
    photoTypeError: "Choisissez une photo JPEG, PNG, WebP, HEIC ou HEIF.",
    photoUploadComplete: "Téléversement privé terminé",
    photoUploadError:
      "Le téléversement privé a été interrompu. La nouvelle tentative utilise la même intention.",
    photoUploadInterrupted: "Téléversement de la photo interrompu",
    photoUploadProgressLabel: "Progression du téléversement de la photo",
    photoUploadStage: "Téléversement privé",
    photoUploading: "Téléversement · {progress}%",
    photoVerificationQueued: "Vérification en file",
    photoVerificationStage: "Vérification",
    photoWaiting: "En attente",
    priceLabel: "Prix annoncé (facultatif)",
    progressLabel: "Étape {current} sur 3",
    queuedStatus: "Décodage en file",
    reacquireDecision: "Réacquérir l’inventaire historique",
    retryAction: "Relancer le décodage",
    retryDescription:
      "Consignez la raison pour laquelle la tâche durable doit être relancée.",
    retryHeading: "Nouvelle tentative possible",
    retryReasonLabel: "Raison de la nouvelle tentative",
    retryWaitStatus: "En attente d’une nouvelle tentative",
    reuseDecision: "Réutiliser le véhicule existant",
    reviewAction: "Consigner la révision du doublon",
    reviewReasonLabel: "Motif de la révision",
    reviewedStatus: "Révision du doublon consignée",
    openDuplicateReviewedStatus:
      "Doublon ouvert approuvé pour une liaison contrôlée au dossier de stock existant.",
    reviewing: "Enregistrement de la révision…",
    runningStatus: "Décodage en cours",
    skipToContent: "Aller à l’entrée d’inventaire",
    startDecodeAction: "Démarrer le décodage du NIV",
    startingDecode: "Démarrage du décodage…",
    stepDecode: "Décodage et révision",
    stepDetails: "Détails de l’inventaire",
    stepVin: "NIV",
    stockDefinitionLabel: "Définition de stock active",
    stockLabel: "Stock",
    succeededStatus: "Décodage terminé",
    suggestionsDescription:
      "Ces suggestions du fournisseur restent modifiables jusqu’à votre confirmation explicite.",
    suggestionsHeading: "Suggestions du véhicule",
    transmissionLabel: "Transmission",
    trimLabel: "Version",
    unavailableValue: "Non fourni",
    vehicleDetailsDescription:
      "Les valeurs par défaut de l’espace sont appliquées. Le stock est attribué seulement à la dernière étape.",
    vehicleDetailsHeading: "Détails de l’inventaire",
    viewInventoryAction: "Voir l’inventaire",
    vinHint:
      "Saisissez ou collez le NIV de 17 caractères. La caméra n’est pas prise en charge.",
    vinLabel: "NIV",
    warningsHeading: "Notes du décodeur",
    workspaceLabel: "Espace de travail",
    workspaceLoading: "Chargement de l’espace…",
  },
} as const;

type WidenStrings<T> = T extends string
  ? string
  : { readonly [Key in keyof T]: WidenStrings<T[Key]> };

export type InventoryIntakeCopy = WidenStrings<
  (typeof inventoryIntakeMessages)["en"]
>;

export type VehiclePhotoJobStatus =
  | "cancelled"
  | "dead_letter"
  | "queued"
  | "retry_wait"
  | "running"
  | "succeeded";

export function vehiclePhotoJobStatusLabel(
  copy: InventoryIntakeCopy,
  status: VehiclePhotoJobStatus,
): string {
  switch (status) {
    case "cancelled":
      return copy.photoJobCancelledStatus;
    case "dead_letter":
      return copy.photoJobDeadLetterStatus;
    case "queued":
      return copy.photoJobQueuedStatus;
    case "retry_wait":
      return copy.photoJobRetryWaitStatus;
    case "running":
      return copy.photoJobRunningStatus;
    case "succeeded":
      return copy.photoJobSucceededStatus;
  }
}
