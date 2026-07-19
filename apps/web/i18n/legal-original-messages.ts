export interface LegalOriginalUploadCopy {
  readonly action: string;
  readonly checksumLabel: string;
  readonly description: string;
  readonly documentLabel: string;
  readonly emptyDocuments: string;
  readonly eyebrow: string;
  readonly fileEmptyError: string;
  readonly fileLabel: string;
  readonly fileSizeError: string;
  readonly fileTypeError: string;
  readonly heading: string;
  readonly jobLabel: string;
  readonly legalKind: string;
  readonly mediaKindLabel: string;
  readonly permissionDenied: string;
  readonly policy: string;
  readonly preparing: string;
  readonly queued: string;
  readonly queuedHint: string;
  readonly queueing: string;
  readonly retryReasonLabel: string;
  readonly retryReasonPlaceholder: string;
  readonly retryReasonRequired: string;
  readonly retryAction: string;
  readonly retryVerificationAction: string;
  readonly signedKind: string;
  readonly signedStepUp: string;
  readonly stageHash: string;
  readonly stageQueued: string;
  readonly stageUpload: string;
  readonly stagesLabel: string;
  readonly startNewUploadAction: string;
  readonly statusChecking: string;
  readonly statusCompleted: string;
  readonly statusDeadLetter: string;
  readonly statusError: string;
  readonly statusQueued: string;
  readonly statusRejected: string;
  readonly statusRetryWait: string;
  readonly statusRunning: string;
  readonly uploadError: string;
  readonly uploadProgressLabel: string;
  readonly uploading: string;
  readonly waiting: string;
}

export const legalOriginalMessages = {
  en: {
    action: "Upload original",
    checksumLabel: "SHA-256",
    description:
      "Choose a generated document and preserve its original bytes through private verification.",
    documentLabel: "Document",
    emptyDocuments: "Generate a document preview before attaching an original.",
    eyebrow: "Preserved source",
    fileEmptyError: "Choose a non-empty file.",
    fileLabel: "PDF or source image",
    fileSizeError: "The original must be 50 MB or smaller.",
    fileTypeError: "Use PDF, JPEG, PNG, WebP, HEIC, or HEIF.",
    heading: "Legal and signed originals",
    jobLabel: "Verification job",
    legalKind: "Legal original",
    mediaKindLabel: "Original type",
    permissionDenied:
      "Your workspace role cannot upload this type of original.",
    policy:
      "The original is never transformed. A private worker scans and verifies the exact bytes before preservation.",
    preparing: "Computing the original checksum…",
    queued: "Verification queued",
    queuedHint:
      "You can leave this screen. The durable verification job will preserve only an exact clean original.",
    queueing: "Queueing private verification…",
    retryReasonLabel: "Reason for retry",
    retryReasonPlaceholder:
      "Confirm why verification should run again (required)",
    retryReasonRequired: "Enter a reason before retrying verification.",
    retryAction: "Retry upload",
    retryVerificationAction: "Retry verification",
    signedKind: "Signed original",
    signedStepUp:
      "Signed originals require documents.upload_signed and strong authentication verified within the last 15 minutes.",
    stageHash: "Fingerprint",
    stageQueued: "Verify",
    stageUpload: "Private upload",
    stagesLabel: "Original upload status",
    startNewUploadAction: "Start a new upload",
    statusChecking: "Checking private verification status…",
    statusCompleted: "Original verified and preserved.",
    statusDeadLetter:
      "Verification stopped after its retry limit. Review it before retrying.",
    statusError:
      "Verification status is temporarily unavailable. We will check again.",
    statusQueued: "Private verification is queued.",
    statusRejected:
      "This original was rejected. Choose the correct file and start a new upload.",
    statusRetryWait: "Verification will retry automatically.",
    statusRunning: "Private verification is running.",
    uploadError:
      "The upload was interrupted or refused. The selected file remains available for retry.",
    uploadProgressLabel: "Legal original upload progress",
    uploading: "Uploading privately…",
    waiting: "Waiting",
  },
  fr: {
    action: "Téléverser l’original",
    checksumLabel: "SHA-256",
    description:
      "Choisissez un document généré et conservez ses octets d’origine après une vérification privée.",
    documentLabel: "Document",
    emptyDocuments:
      "Générez un aperçu de document avant de joindre un original.",
    eyebrow: "Source conservée",
    fileEmptyError: "Choisissez un fichier non vide.",
    fileLabel: "PDF ou image source",
    fileSizeError: "L’original doit avoir une taille maximale de 50 Mo.",
    fileTypeError: "Utilisez un PDF, JPEG, PNG, WebP, HEIC ou HEIF.",
    heading: "Originaux légaux et signés",
    jobLabel: "Tâche de vérification",
    legalKind: "Original légal",
    mediaKindLabel: "Type d’original",
    permissionDenied:
      "Votre rôle dans l’espace ne permet pas ce type de téléversement.",
    policy:
      "L’original n’est jamais transformé. Un worker privé analyse et vérifie les octets exacts avant leur conservation.",
    preparing: "Calcul de l’empreinte de l’original…",
    queued: "Vérification en file",
    queuedHint:
      "Vous pouvez quitter cet écran. La tâche durable ne conservera qu’un original exact et sain.",
    queueing: "Mise en file de la vérification privée…",
    retryReasonLabel: "Motif de la nouvelle tentative",
    retryReasonPlaceholder:
      "Confirmez pourquoi la vérification doit recommencer (obligatoire)",
    retryReasonRequired:
      "Saisissez un motif avant de relancer la vérification.",
    retryAction: "Réessayer le téléversement",
    retryVerificationAction: "Relancer la vérification",
    signedKind: "Original signé",
    signedStepUp:
      "Les originaux signés exigent documents.upload_signed et une authentification forte vérifiée dans les 15 dernières minutes.",
    stageHash: "Empreinte",
    stageQueued: "Vérifier",
    stageUpload: "Téléversement privé",
    stagesLabel: "État du téléversement de l’original",
    startNewUploadAction: "Commencer un nouveau téléversement",
    statusChecking: "Vérification de l’état privé en cours…",
    statusCompleted: "Original vérifié et conservé.",
    statusDeadLetter:
      "La vérification s’est arrêtée après la limite de tentatives. Examinez-la avant de la relancer.",
    statusError:
      "L’état de la vérification est temporairement indisponible. Nous réessaierons.",
    statusQueued: "La vérification privée est en file.",
    statusRejected:
      "Cet original a été rejeté. Choisissez le bon fichier et commencez un nouveau téléversement.",
    statusRetryWait: "La vérification sera relancée automatiquement.",
    statusRunning: "La vérification privée est en cours.",
    uploadError:
      "Le téléversement a été interrompu ou refusé. Le fichier sélectionné reste disponible pour réessayer.",
    uploadProgressLabel: "Progression du téléversement de l’original légal",
    uploading: "Téléversement privé…",
    waiting: "En attente",
  },
} as const satisfies Readonly<Record<"en" | "fr", LegalOriginalUploadCopy>>;
