import type { Locale } from "./messages";

type CommonKey =
  | "appName"
  | "attention"
  | "back"
  | "cancel"
  | "configuration"
  | "deals"
  | "documents"
  | "environment"
  | "errorDescription"
  | "errorHeading"
  | "exports"
  | "loading"
  | "localeLabel"
  | "navigationLabel"
  | "offline"
  | "people"
  | "reports"
  | "retry"
  | "save"
  | "saved"
  | "saving"
  | "skipToContent"
  | "workspaceLabel";

type DocumentKey =
  | "actionReason"
  | "actionReasonHint"
  | "available"
  | "availabilityHint"
  | "calculationReady"
  | "calculationEvidence"
  | "checksum"
  | "confirmAllocation"
  | "confirmAllocationHint"
  | "created"
  | "dealId"
  | "detailEyebrow"
  | "detailHeading"
  | "detailSummary"
  | "documentDate"
  | "documentFields"
  | "documentFieldsHint"
  | "documentType"
  | "download"
  | "emptyDescription"
  | "emptyHeading"
  | "evidenceHint"
  | "fieldInvalidJson"
  | "files"
  | "generation"
  | "generationQueued"
  | "generationResult"
  | "heading"
  | "intendedSignatureDate"
  | "jobHistory"
  | "jobId"
  | "lineage"
  | "listEyebrow"
  | "locale"
  | "markSigned"
  | "markSignedHint"
  | "mode"
  | "noFiles"
  | "noJobs"
  | "noLineage"
  | "notProductionReady"
  | "officialAction"
  | "officialNumber"
  | "officialUnavailable"
  | "openDocument"
  | "previewAction"
  | "previewHint"
  | "previewNumberPolicy"
  | "previewReady"
  | "queue"
  | "refresh"
  | "renderAttempts"
  | "renderFailed"
  | "retryRender"
  | "signedAt"
  | "signedUpload"
  | "snapshot"
  | "status"
  | "summary"
  | "supersede"
  | "supersedeHint"
  | "taxReady"
  | "taxEvidence"
  | "templateReady"
  | "templateVersionId"
  | "typeUnavailable"
  | "validateAction"
  | "validation"
  | "validationErrors"
  | "validationPassed"
  | "validationRequired"
  | "validationWarnings"
  | "version"
  | "voidAction"
  | "voidHint"
  | "voidReason";

type ConfigurationKey =
  | "activate"
  | "allocationEvent"
  | "activationHint"
  | "approvalAttachment"
  | "approvalConditions"
  | "approvalDecision"
  | "approvalExpires"
  | "approvalHeading"
  | "approvalOrganization"
  | "approvalReason"
  | "approvalRole"
  | "approvalType"
  | "approvals"
  | "approve"
  | "artifact"
  | "calculationHeading"
  | "calculationPreview"
  | "calculationPreviewInputs"
  | "calculationValidate"
  | "calculationDefinition"
  | "checksum"
  | "createApproval"
  | "createNumberingVersion"
  | "currentOnly"
  | "dealId"
  | "dealInputHint"
  | "effective"
  | "empty"
  | "expectedChecksum"
  | "fixtureEvidence"
  | "formatPattern"
  | "heading"
  | "importPolicy"
  | "increment"
  | "jurisdiction"
  | "latestApproval"
  | "newVersion"
  | "numberingHeading"
  | "numberingHint"
  | "numericWidth"
  | "prefix"
  | "periodAnchor"
  | "periodMonths"
  | "previewOutput"
  | "reason"
  | "refresh"
  | "resetPolicy"
  | "scope"
  | "semanticVersion"
  | "source"
  | "startingValue"
  | "status"
  | "stepUpHint"
  | "suffix"
  | "summary"
  | "taxContext"
  | "taxCurrency"
  | "taxDate"
  | "taxHeading"
  | "taxInputs"
  | "taxPreview"
  | "timezone"
  | "validateOutput"
  | "validationEvidence"
  | "version";

type ExportKey =
  | "aging"
  | "columns"
  | "created"
  | "dateFrom"
  | "dateTo"
  | "deals"
  | "definition"
  | "download"
  | "emptyDefinitions"
  | "emptyReport"
  | "expires"
  | "exportHeading"
  | "filters"
  | "format"
  | "generate"
  | "generated"
  | "gross"
  | "heading"
  | "leads"
  | "locationId"
  | "maximumRows"
  | "permission"
  | "reason"
  | "refresh"
  | "reportHeading"
  | "reportHint"
  | "rowCount"
  | "runHeading"
  | "runQueued"
  | "sensitivity"
  | "stepUp"
  | "summary";

export interface M4Messages {
  readonly common: Readonly<Record<CommonKey, string>> & {
    readonly localeNames: Readonly<Record<Locale, string>>;
  };
  readonly configuration: Readonly<Record<ConfigurationKey, string>> & {
    readonly artifactTypes: Readonly<Record<string, string>>;
    readonly decisions: Readonly<Record<string, string>>;
    readonly importPolicies: Readonly<Record<string, string>>;
    readonly resetPolicies: Readonly<Record<string, string>>;
    readonly scopeTypes: Readonly<Record<string, string>>;
    readonly statuses: Readonly<Record<string, string>>;
  };
  readonly documents: Readonly<Record<DocumentKey, string>> & {
    readonly fileRoles: Readonly<
      Record<
        | "attachment"
        | "generated_original"
        | "preview"
        | "signed_scan"
        | "void_notice",
        string
      >
    >;
    readonly jobStatuses: Readonly<
      Record<
        | "cancelled"
        | "dead_letter"
        | "queued"
        | "retry_wait"
        | "running"
        | "succeeded",
        string
      >
    >;
    readonly modes: Readonly<Record<"official" | "preview", string>>;
    readonly statuses: Readonly<
      Record<
        | "completed"
        | "failed"
        | "generation_failed"
        | "generated"
        | "generating"
        | "queued"
        | "signed_received"
        | "superseded"
        | "voided",
        string
      >
    >;
  };
  readonly exports: Readonly<Record<ExportKey, string>> & {
    readonly reportFields: Readonly<Record<string, string>>;
    readonly statuses: Readonly<Record<string, string>>;
  };
  readonly fieldLabels: Readonly<Record<string, string>>;
}

const en: M4Messages = {
  common: {
    appName: "Vynlo",
    attention: "Needs attention",
    back: "Back",
    cancel: "Cancel",
    configuration: "Configuration",
    deals: "Deals",
    documents: "Documents",
    environment: "Development",
    errorDescription:
      "Your input is preserved. Retry or refresh the latest immutable record before continuing.",
    errorHeading: "The operation could not be completed",
    exports: "Exports",
    loading: "Loading…",
    localeLabel: "Language",
    localeNames: { en: "English", fr: "Français" },
    navigationLabel: "Operational workspaces",
    offline: "Offline — previews, official actions, and exports are disabled.",
    people: "People",
    reports: "Reports",
    retry: "Retry",
    save: "Save",
    saved: "Saved",
    saving: "Saving…",
    skipToContent: "Skip to content",
    workspaceLabel: "Workspace",
  },
  documents: {
    actionReason: "Reason",
    actionReasonHint: "This reason becomes permanent audit evidence.",
    available: "Available document types",
    availabilityHint:
      "Availability reflects the exact active type, template, numbering, calculation, and tax configuration.",
    calculationReady: "Calculation",
    calculationEvidence: "Calculation evidence (optional JSON object)",
    checksum: "Checksum",
    confirmAllocation:
      "I understand an official number will be allocated permanently.",
    confirmAllocationHint:
      "Official numbers are never reused, including after a render failure, void, or supersession.",
    created: "Created",
    dealId: "Deal ID",
    detailEyebrow: "Document record",
    detailHeading: "Official document detail",
    detailSummary:
      "Inspect exact versions, generated and signed files, render attempts, and permanent lineage.",
    documentDate: "Document date",
    documentFields: "Document fields",
    documentFieldsHint:
      "Fields come from the selected immutable schema. Complex rows accept a JSON array or object.",
    documentType: "Document type",
    download: "Secure download",
    emptyDescription:
      "Choose an available type, validate its fields, then create an unnumbered preview.",
    emptyHeading: "No documents match this queue",
    evidenceHint:
      "Paste only evidence returned by an exact calculation or tax preview. The server revalidates every version and checksum.",
    fieldInvalidJson: "Enter valid JSON for this structured field.",
    files: "Immutable files",
    generation: "Generate document",
    generationQueued: "The durable render job is queued.",
    generationResult: "Generation receipt",
    heading: "Document operations",
    intendedSignatureDate: "Intended signature date",
    jobHistory: "Render job history",
    jobId: "Job ID",
    lineage: "Lineage",
    listEyebrow: "Documents and numbering",
    locale: "Document language",
    markSigned: "Mark document signed",
    markSignedHint:
      "Only mark signed after the verified signed scan appears in the immutable file history.",
    mode: "Mode",
    noFiles: "No generated or signed files have been recorded.",
    noJobs: "No render attempts have been recorded.",
    noLineage: "This document does not supersede another record.",
    notProductionReady: "Preview only — production approval is not active.",
    officialAction: "Allocate number and generate official PDF",
    officialNumber: "Official number",
    officialUnavailable:
      "Official generation is unavailable until every gate passes.",
    openDocument: "Open document",
    previewAction: "Generate unnumbered preview",
    previewHint:
      "Preview PDFs are watermarked and never consume an official number.",
    previewNumberPolicy: "No official number is allocated during preview.",
    previewReady: "Preview",
    queue: "Document queue",
    refresh: "Refresh queue",
    renderAttempts: "Attempts",
    renderFailed:
      "Review the failure. Retry with the same number and snapshot, or void the document while preserving its failure evidence and consumed number.",
    retryRender: "Retry same render",
    signedAt: "Signed at",
    signedUpload: "Upload signed scan",
    snapshot: "Pinned version snapshot",
    status: "Status",
    summary:
      "Validate fields, preview without a number, and allocate an official number only with explicit confirmation.",
    supersede: "Create superseding document",
    supersedeHint:
      "A corrected official document receives a new permanent number. The original remains unchanged.",
    taxReady: "Tax",
    taxEvidence: "Tax evidence (optional JSON object)",
    templateReady: "Template",
    templateVersionId: "Template version ID",
    typeUnavailable: "No eligible active type is available for this language.",
    validateAction: "Validate fields and dependencies",
    validation: "Validation gates",
    validationErrors: "Blocking gates",
    validationPassed: "Every required gate passed for this exact input.",
    validationRequired: "Validate the current input before generating.",
    validationWarnings: "Warnings",
    version: "Version",
    voidAction: "Void official document",
    voidHint:
      "Voiding is permanent, may require recent strong authentication, and never returns the number to its sequence. Voiding a failed replacement preserves its failure evidence and permits a fresh successor.",
    voidReason: "Reason for voiding",
    fileRoles: {
      attachment: "Attachment",
      generated_original: "Generated original",
      preview: "Watermarked preview",
      signed_scan: "Signed scan",
      void_notice: "Void notice",
    },
    jobStatuses: {
      cancelled: "Cancelled",
      dead_letter: "Needs review",
      queued: "Queued",
      retry_wait: "Retry scheduled",
      running: "Rendering",
      succeeded: "Completed",
    },
    modes: { official: "Official", preview: "Preview" },
    statuses: {
      completed: "Completed",
      failed: "Render failed",
      generation_failed: "Official generation failed",
      generated: "Generated",
      generating: "Generating",
      queued: "Queued",
      signed_received: "Signed scan received",
      superseded: "Superseded",
      voided: "Voided",
    },
  },
  configuration: {
    activate: "Activate exact version",
    allocationEvent: "Allocation permission key",
    activationHint:
      "Activation requires permission, recent strong authentication, passed fixtures, exact checksum, approvals, and a reason.",
    approvalAttachment: "Evidence reference",
    approvalConditions: "Conditions (JSON object)",
    approvalDecision: "Decision",
    approvalExpires: "Expires at",
    approvalHeading: "Approval evidence",
    approvalOrganization: "Professional organization",
    approvalReason: "Decision reason",
    approvalRole: "Professional role",
    approvalType: "Approval type",
    approvals: "Append-only approvals",
    approve: "Approve exact calculation version",
    artifact: "Artifact version",
    calculationHeading: "Calculations",
    calculationPreview: "Run calculation preview",
    calculationPreviewInputs: "Preview inputs (JSON object)",
    calculationValidate: "Validate declarative definition",
    calculationDefinition: "Definition (JSON object)",
    checksum: "Checksum",
    createApproval: "Record approval decision",
    createNumberingVersion: "Create tested version",
    currentOnly: "Show current approvals only",
    dealId: "Deal ID for official evidence",
    dealInputHint:
      "When a deal ID is provided, the server derives the calculation and tax inputs from the current deal and ignores the JSON input fields below.",
    effective: "Effective dates",
    empty: "No configured versions are available in this workspace.",
    expectedChecksum: "Expected SHA-256 checksum",
    fixtureEvidence: "Fixture evidence (JSON object)",
    formatPattern: "Format pattern",
    heading: "Versioned configuration",
    importPolicy: "Import policy",
    increment: "Increment",
    jurisdiction: "Jurisdiction",
    latestApproval: "Approval",
    newVersion: "New numbering version",
    numberingHeading: "Numbering",
    numberingHint:
      "Sequences are declarative, workspace-scoped, immutable after activation, and configured for never reuse.",
    numericWidth: "Sequence width",
    prefix: "Prefix",
    periodAnchor: "Period anchor",
    periodMonths: "Period length (months)",
    previewOutput: "Preview output",
    reason: "Change reason",
    refresh: "Refresh configuration",
    resetPolicy: "Reset policy",
    scope: "Scope",
    semanticVersion: "Semantic version",
    source: "Source",
    startingValue: "Starting value",
    status: "Lifecycle status",
    stepUpHint:
      "Activation is a sensitive action and may require recent strong authentication.",
    suffix: "Suffix",
    summary:
      "Review checksums, validation evidence, approvals, and activation gates without rewriting history.",
    taxContext: "Tax context",
    taxCurrency: "Currency",
    taxDate: "Transaction date",
    taxHeading: "Tax packs",
    taxInputs: "Tax inputs (JSON object)",
    taxPreview: "Run tax preview",
    timezone: "Timezone",
    validateOutput: "Validation result",
    validationEvidence: "Validation evidence (JSON object)",
    version: "Version",
    artifactTypes: {
      calculation: "Calculation",
      numbering_definition: "Numbering definition",
      tax_pack: "Tax pack",
    },
    decisions: {
      approved: "Approved",
      rejected: "Rejected",
      revoked: "Revoked",
    },
    importPolicies: {
      authorized_reservation: "Authorized reservation",
      prohibited: "Prohibited",
    },
    resetPolicies: {
      configured_period: "Configured period",
      monthly: "Monthly",
      never: "Never",
      yearly: "Yearly",
    },
    scopeTypes: {
      combined: "Combined dimensions",
      document_type: "Document type",
      legal_entity: "Legal entity",
      location: "Location",
      workspace: "Workspace",
    },
    statuses: {
      active: "Active",
      approved: "Approved",
      draft: "Draft",
      retired: "Retired",
      test_passed: "Tests passed",
      validated: "Validated",
    },
  },
  exports: {
    aging: "Inventory aging",
    columns: "Columns",
    created: "Requested",
    dateFrom: "From date",
    dateTo: "To date",
    deals: "Deals",
    definition: "Export definition",
    download: "Download verified file",
    emptyDefinitions: "No active export definitions are available.",
    emptyReport: "No rows match these report filters.",
    expires: "Expires",
    exportHeading: "Configured exports",
    filters: "Filters (JSON object)",
    format: "File format",
    generate: "Generate export",
    generated: "Generated file",
    gross: "Inventory gross",
    heading: "Exports and reports",
    leads: "Leads",
    locationId: "Location ID",
    maximumRows: "Maximum rows",
    permission: "Required permission",
    reason: "Export reason",
    refresh: "Refresh report",
    reportHeading: "Operational reports",
    reportHint:
      "The same authorized report rows remain readable on a phone before any file is generated.",
    rowCount: "Rows",
    runHeading: "Latest export run",
    runQueued:
      "The durable export job is queued. Status updates remain visible here.",
    sensitivity: "Sensitivity",
    stepUp: "Recent strong authentication required",
    summary:
      "Review phone-usable operational reports, then generate deterministic CSV or XLSX files from active definitions.",
    statuses: {
      dead_letter: "Needs review",
      expired: "Expired",
      failed: "Failed",
      generated: "Generated",
      queued: "Queued",
      retry_wait: "Retry scheduled",
      running: "Generating",
    },
    reportFields: {
      acquired_on: "Acquired",
      age_days: "Age (days)",
      closed_at: "Closed",
      converted_deal_id: "Converted deal",
      cost_amount_minor: "Cost",
      created_at: "Created",
      currency_code: "Currency",
      deal_id: "Deal",
      deal_type_key: "Deal type",
      gross_amount_minor: "Gross",
      inventory_unit_id: "Inventory unit",
      last_activity_at: "Last activity",
      location_id: "Location",
      make: "Make",
      model: "Model",
      model_year: "Year",
      owner_membership_id: "Owner",
      revenue_amount_minor: "Revenue",
      source_key: "Source",
      status: "Status",
      stock_number: "Stock number",
      total_amount_minor: "Total",
      updated_at: "Updated",
    },
  },
  fieldLabels: {
    acquisition_date: "Acquisition date",
    allowance_minor: "Allowance (minor units)",
    applicant_party_id: "Applicant party ID",
    approved_amount_minor: "Approved amount (minor units)",
    balance_due_minor: "Balance due (minor units)",
    buyer_party_id: "Buyer party ID",
    cash_price_minor: "Cash price (minor units)",
    condition_notes: "Condition notes",
    conditions: "Conditions",
    currency_code: "Currency code",
    customer_party_id: "Customer party ID",
    deal_id: "Deal ID",
    delivery_date: "Delivery date",
    deposit_minor: "Deposit (minor units)",
    document_date: "Document date",
    fee_lines: "Fee lines",
    finance_application_id: "Finance application ID",
    inventory_unit_id: "Inventory unit ID",
    lender_party_id: "Lender party ID",
    lender_reference: "Lender reference",
    lien_amount_minor: "Lien amount (minor units)",
    lien_declared: "Lien declared",
    lien_payoff_minor: "Lien payoff (minor units)",
    lines: "Line items",
    location_id: "Location ID",
    notes: "Notes",
    odometer_unit: "Odometer unit",
    odometer_value: "Odometer value",
    owner_party_id: "Owner party ID",
    ownership_document_refs: "Ownership document references",
    purchase_price_minor: "Purchase price (minor units)",
    returned_rate_bps: "Returned rate (basis points)",
    returned_term_months: "Returned term (months)",
    seller_legal_entity_id: "Seller legal entity ID",
    seller_party_id: "Seller party ID",
    stock_number: "Stock number",
    tax_eligibility_inputs: "Tax eligibility inputs",
    tax_profile_version_id: "Tax profile version ID",
    trade_in_ids: "Trade-in IDs",
    vin: "VIN",
  },
};

const fr: M4Messages = {
  common: {
    appName: "Vynlo",
    attention: "À examiner",
    back: "Retour",
    cancel: "Annuler",
    configuration: "Configuration",
    deals: "Dossiers",
    documents: "Documents",
    environment: "Développement",
    errorDescription:
      "Votre saisie est conservée. Réessayez ou actualisez l’enregistrement immuable avant de continuer.",
    errorHeading: "L’opération n’a pas pu être terminée",
    exports: "Exports",
    loading: "Chargement…",
    localeLabel: "Langue",
    localeNames: { en: "English", fr: "Français" },
    navigationLabel: "Espaces opérationnels",
    offline: "Hors ligne — aperçus, documents officiels et exports désactivés.",
    people: "Clients",
    reports: "Rapports",
    retry: "Réessayer",
    save: "Enregistrer",
    saved: "Enregistré",
    saving: "Enregistrement…",
    skipToContent: "Aller au contenu",
    workspaceLabel: "Espace de travail",
  },
  documents: {
    actionReason: "Motif",
    actionReasonHint: "Ce motif devient une preuve d’audit permanente.",
    available: "Types de documents disponibles",
    availabilityHint:
      "La disponibilité reflète exactement le type, le modèle, la numérotation, les calculs et les taxes actifs.",
    calculationReady: "Calcul",
    calculationEvidence: "Preuve de calcul (objet JSON facultatif)",
    checksum: "Somme de contrôle",
    confirmAllocation:
      "Je comprends qu’un numéro officiel sera attribué définitivement.",
    confirmAllocationHint:
      "Les numéros officiels ne sont jamais réutilisés, même après un échec, une annulation ou un remplacement.",
    created: "Créé",
    dealId: "ID du dossier",
    detailEyebrow: "Enregistrement documentaire",
    detailHeading: "Détail du document officiel",
    detailSummary:
      "Consultez les versions exactes, les fichiers, les tentatives de rendu et la filiation permanente.",
    documentDate: "Date du document",
    documentFields: "Champs du document",
    documentFieldsHint:
      "Les champs proviennent du schéma immuable sélectionné. Les lignes complexes acceptent un tableau ou objet JSON.",
    documentType: "Type de document",
    download: "Téléchargement sécurisé",
    emptyDescription:
      "Choisissez un type disponible, validez les champs, puis créez un aperçu non numéroté.",
    emptyHeading: "Aucun document ne correspond à cette file",
    evidenceHint:
      "Collez uniquement la preuve retournée par un aperçu exact de calcul ou de taxes. Le serveur revalide chaque version et somme.",
    fieldInvalidJson: "Saisissez un JSON valide pour ce champ structuré.",
    files: "Fichiers immuables",
    generation: "Générer le document",
    generationQueued: "La tâche durable de rendu est en file.",
    generationResult: "Reçu de génération",
    heading: "Opérations documentaires",
    intendedSignatureDate: "Date de signature prévue",
    jobHistory: "Historique des rendus",
    jobId: "ID de tâche",
    lineage: "Filiation",
    listEyebrow: "Documents et numérotation",
    locale: "Langue du document",
    markSigned: "Marquer comme signé",
    markSignedHint:
      "Marquez le document signé seulement après l’apparition de la copie vérifiée dans l’historique immuable.",
    mode: "Mode",
    noFiles: "Aucun fichier généré ou signé n’a été enregistré.",
    noJobs: "Aucune tentative de rendu n’a été enregistrée.",
    noLineage: "Ce document ne remplace aucun enregistrement.",
    notProductionReady:
      "Aperçu seulement — l’approbation de production n’est pas active.",
    officialAction: "Attribuer un numéro et générer le PDF officiel",
    officialNumber: "Numéro officiel",
    officialUnavailable:
      "La génération officielle reste indisponible tant que tous les contrôles n’ont pas réussi.",
    openDocument: "Ouvrir le document",
    previewAction: "Générer un aperçu non numéroté",
    previewHint:
      "Les aperçus sont filigranés et ne consomment jamais de numéro officiel.",
    previewNumberPolicy:
      "Aucun numéro officiel n’est attribué pendant l’aperçu.",
    previewReady: "Aperçu",
    queue: "File de documents",
    refresh: "Actualiser la file",
    renderAttempts: "Tentatives",
    renderFailed:
      "Examinez l’échec. Relancez le rendu avec le même numéro et le même instantané, ou annulez le document en conservant la preuve d’échec et le numéro consommé.",
    retryRender: "Relancer le même rendu",
    signedAt: "Signé le",
    signedUpload: "Téléverser la copie signée",
    snapshot: "Instantané des versions liées",
    status: "État",
    summary:
      "Validez les champs, créez un aperçu sans numéro et attribuez un numéro officiel uniquement après confirmation explicite.",
    supersede: "Créer un document de remplacement",
    supersedeHint:
      "Un document officiel corrigé reçoit un nouveau numéro permanent. L’original reste inchangé.",
    taxReady: "Taxes",
    taxEvidence: "Preuve fiscale (objet JSON facultatif)",
    templateReady: "Modèle",
    templateVersionId: "ID de version du modèle",
    typeUnavailable:
      "Aucun type actif admissible n’est disponible dans cette langue.",
    validateAction: "Valider les champs et dépendances",
    validation: "Contrôles de validation",
    validationErrors: "Contrôles bloquants",
    validationPassed:
      "Tous les contrôles requis ont réussi pour cette saisie exacte.",
    validationRequired: "Validez la saisie actuelle avant de générer.",
    validationWarnings: "Avertissements",
    version: "Version",
    voidAction: "Annuler le document officiel",
    voidHint:
      "L’annulation est permanente, peut exiger une authentification forte récente et ne remet jamais le numéro dans la séquence. L’annulation d’un remplacement échoué conserve sa preuve d’échec et permet de créer un nouveau successeur.",
    voidReason: "Motif d’annulation",
    fileRoles: {
      attachment: "Pièce jointe",
      generated_original: "Original généré",
      preview: "Aperçu filigrané",
      signed_scan: "Copie signée",
      void_notice: "Avis d’annulation",
    },
    jobStatuses: {
      cancelled: "Annulée",
      dead_letter: "À examiner",
      queued: "En file",
      retry_wait: "Nouvelle tentative prévue",
      running: "Rendu en cours",
      succeeded: "Terminée",
    },
    modes: { official: "Officiel", preview: "Aperçu" },
    statuses: {
      completed: "Terminé",
      failed: "Échec du rendu",
      generation_failed: "Échec de la génération officielle",
      generated: "Généré",
      generating: "Génération",
      queued: "En file",
      signed_received: "Copie signée reçue",
      superseded: "Remplacé",
      voided: "Annulé",
    },
  },
  configuration: {
    activate: "Activer la version exacte",
    allocationEvent: "Clé de permission d’attribution",
    activationHint:
      "L’activation exige la permission, une authentification forte récente, les tests réussis, la somme exacte, les approbations et un motif.",
    approvalAttachment: "Référence de preuve",
    approvalConditions: "Conditions (objet JSON)",
    approvalDecision: "Décision",
    approvalExpires: "Expire le",
    approvalHeading: "Preuves d’approbation",
    approvalOrganization: "Organisation professionnelle",
    approvalReason: "Motif de la décision",
    approvalRole: "Rôle professionnel",
    approvalType: "Type d’approbation",
    approvals: "Approbations en ajout seulement",
    approve: "Approuver la version exacte du calcul",
    artifact: "Version de l’artefact",
    calculationHeading: "Calculs",
    calculationPreview: "Exécuter l’aperçu du calcul",
    calculationPreviewInputs: "Entrées d’aperçu (objet JSON)",
    calculationValidate: "Valider la définition déclarative",
    calculationDefinition: "Définition (objet JSON)",
    checksum: "Somme de contrôle",
    createApproval: "Enregistrer la décision",
    createNumberingVersion: "Créer la version testée",
    currentOnly: "Afficher seulement les approbations actuelles",
    dealId: "ID du dossier pour la preuve officielle",
    dealInputHint:
      "Lorsqu’un ID de dossier est fourni, le serveur dérive les entrées de calcul et de taxes du dossier actuel et ignore les champs JSON ci-dessous.",
    effective: "Dates d’effet",
    empty: "Aucune version configurée n’est disponible dans cet espace.",
    expectedChecksum: "Somme SHA-256 attendue",
    fixtureEvidence: "Preuves des tests (objet JSON)",
    formatPattern: "Motif de format",
    heading: "Configuration versionnée",
    importPolicy: "Politique d’importation",
    increment: "Incrément",
    jurisdiction: "Juridiction",
    latestApproval: "Approbation",
    newVersion: "Nouvelle version de numérotation",
    numberingHeading: "Numérotation",
    numberingHint:
      "Les séquences sont déclaratives, liées à l’espace, immuables après activation et ne réutilisent jamais un numéro.",
    numericWidth: "Largeur de séquence",
    prefix: "Préfixe",
    periodAnchor: "Début de la période",
    periodMonths: "Durée de la période (mois)",
    previewOutput: "Résultat de l’aperçu",
    reason: "Motif du changement",
    refresh: "Actualiser la configuration",
    resetPolicy: "Politique de remise à zéro",
    scope: "Portée",
    semanticVersion: "Version sémantique",
    source: "Source",
    startingValue: "Valeur initiale",
    status: "État du cycle de vie",
    stepUpHint:
      "L’activation est sensible et peut exiger une authentification forte récente.",
    suffix: "Suffixe",
    summary:
      "Examinez les sommes de contrôle, les preuves, les approbations et les contrôles d’activation sans réécrire l’historique.",
    taxContext: "Contexte fiscal",
    taxCurrency: "Devise",
    taxDate: "Date de transaction",
    taxHeading: "Ensembles fiscaux",
    taxInputs: "Entrées fiscales (objet JSON)",
    taxPreview: "Exécuter l’aperçu fiscal",
    timezone: "Fuseau horaire",
    validateOutput: "Résultat de validation",
    validationEvidence: "Preuves de validation (objet JSON)",
    version: "Version",
    artifactTypes: {
      calculation: "Calcul",
      numbering_definition: "Définition de numérotation",
      tax_pack: "Ensemble fiscal",
    },
    decisions: {
      approved: "Approuvée",
      rejected: "Rejetée",
      revoked: "Révoquée",
    },
    importPolicies: {
      authorized_reservation: "Réservation autorisée",
      prohibited: "Interdite",
    },
    resetPolicies: {
      configured_period: "Période configurée",
      monthly: "Mensuelle",
      never: "Jamais",
      yearly: "Annuelle",
    },
    scopeTypes: {
      combined: "Dimensions combinées",
      document_type: "Type de document",
      legal_entity: "Entité juridique",
      location: "Emplacement",
      workspace: "Espace de travail",
    },
    statuses: {
      active: "Active",
      approved: "Approuvée",
      draft: "Brouillon",
      retired: "Retirée",
      test_passed: "Tests réussis",
      validated: "Validée",
    },
  },
  exports: {
    aging: "Âge de l’inventaire",
    columns: "Colonnes",
    created: "Demandé",
    dateFrom: "Date de début",
    dateTo: "Date de fin",
    deals: "Dossiers",
    definition: "Définition d’export",
    download: "Télécharger le fichier vérifié",
    emptyDefinitions: "Aucune définition d’export active n’est disponible.",
    emptyReport: "Aucune ligne ne correspond à ces filtres.",
    expires: "Expire",
    exportHeading: "Exports configurés",
    filters: "Filtres (objet JSON)",
    format: "Format du fichier",
    generate: "Générer l’export",
    generated: "Fichier généré",
    gross: "Marge d’inventaire",
    heading: "Exports et rapports",
    leads: "Prospects",
    locationId: "ID de l’emplacement",
    maximumRows: "Nombre maximal de lignes",
    permission: "Permission requise",
    reason: "Motif de l’export",
    refresh: "Actualiser le rapport",
    reportHeading: "Rapports opérationnels",
    reportHint:
      "Les mêmes lignes autorisées restent lisibles sur téléphone avant toute génération de fichier.",
    rowCount: "Lignes",
    runHeading: "Dernier export",
    runQueued:
      "La tâche durable d’export est en file. Son état reste visible ici.",
    sensitivity: "Sensibilité",
    stepUp: "Authentification forte récente requise",
    summary:
      "Consultez les rapports opérationnels sur téléphone, puis générez des fichiers CSV ou XLSX déterministes.",
    statuses: {
      dead_letter: "À examiner",
      expired: "Expiré",
      failed: "Échec",
      generated: "Généré",
      queued: "En file",
      retry_wait: "Nouvelle tentative prévue",
      running: "Génération",
    },
    reportFields: {
      acquired_on: "Acquis",
      age_days: "Âge (jours)",
      closed_at: "Fermé",
      converted_deal_id: "Dossier converti",
      cost_amount_minor: "Coût",
      created_at: "Créé",
      currency_code: "Devise",
      deal_id: "Dossier",
      deal_type_key: "Type de dossier",
      gross_amount_minor: "Marge",
      inventory_unit_id: "Unité d’inventaire",
      last_activity_at: "Dernière activité",
      location_id: "Emplacement",
      make: "Marque",
      model: "Modèle",
      model_year: "Année",
      owner_membership_id: "Responsable",
      revenue_amount_minor: "Revenu",
      source_key: "Source",
      status: "État",
      stock_number: "Numéro de stock",
      total_amount_minor: "Total",
      updated_at: "Mis à jour",
    },
  },
  fieldLabels: {
    acquisition_date: "Date d’acquisition",
    allowance_minor: "Allocation (unités mineures)",
    applicant_party_id: "ID de la partie demanderesse",
    approved_amount_minor: "Montant approuvé (unités mineures)",
    balance_due_minor: "Solde dû (unités mineures)",
    buyer_party_id: "ID de l’acheteur",
    cash_price_minor: "Prix comptant (unités mineures)",
    condition_notes: "Notes sur l’état",
    conditions: "Conditions",
    currency_code: "Code de devise",
    customer_party_id: "ID du client",
    deal_id: "ID du dossier",
    delivery_date: "Date de livraison",
    deposit_minor: "Dépôt (unités mineures)",
    document_date: "Date du document",
    fee_lines: "Lignes de frais",
    finance_application_id: "ID de la demande de financement",
    inventory_unit_id: "ID de l’unité d’inventaire",
    lender_party_id: "ID du prêteur",
    lender_reference: "Référence du prêteur",
    lien_amount_minor: "Montant du privilège (unités mineures)",
    lien_declared: "Privilège déclaré",
    lien_payoff_minor: "Remboursement du privilège (unités mineures)",
    lines: "Lignes",
    location_id: "ID de l’emplacement",
    notes: "Notes",
    odometer_unit: "Unité de l’odomètre",
    odometer_value: "Valeur de l’odomètre",
    owner_party_id: "ID du propriétaire",
    ownership_document_refs: "Références des titres de propriété",
    purchase_price_minor: "Prix d’achat (unités mineures)",
    returned_rate_bps: "Taux retourné (points de base)",
    returned_term_months: "Durée retournée (mois)",
    seller_legal_entity_id: "ID de l’entité juridique vendeuse",
    seller_party_id: "ID du vendeur",
    stock_number: "Numéro de stock",
    tax_eligibility_inputs: "Entrées d’admissibilité fiscale",
    tax_profile_version_id: "ID de version du profil fiscal",
    trade_in_ids: "ID des véhicules d’échange",
    vin: "NIV",
  },
};

export const m4Messages: Readonly<Record<Locale, M4Messages>> = Object.freeze({
  en,
  fr,
});
