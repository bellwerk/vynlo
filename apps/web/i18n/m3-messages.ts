import type { Locale } from "./messages";

export interface M3Messages {
  readonly common: {
    readonly appName: string;
    readonly appointments: string;
    readonly attention: string;
    readonly back: string;
    readonly cancel: string;
    readonly close: string;
    readonly continue: string;
    readonly create: string;
    readonly deals: string;
    readonly details: string;
    readonly environment: string;
    readonly errorDescription: string;
    readonly errorHeading: string;
    readonly leads: string;
    readonly loading: string;
    readonly localeLabel: string;
    readonly localeNames: Readonly<Record<Locale, string>>;
    readonly navigationLabel: string;
    readonly offline: string;
    readonly parties: string;
    readonly retry: string;
    readonly required: string;
    readonly save: string;
    readonly saved: string;
    readonly saving: string;
    readonly skipToContent: string;
    readonly tasks: string;
    readonly status: string;
    readonly view: string;
    readonly workspaceLabel: string;
  };
  readonly crm: {
    readonly addActivity: string;
    readonly addAddress: string;
    readonly addAppointment: string;
    readonly addContact: string;
    readonly addRelationship: string;
    readonly addTask: string;
    readonly addressType: string;
    readonly addresses: string;
    readonly allowed: string;
    readonly appointmentEmpty: string;
    readonly appointmentHeading: string;
    readonly appointmentNotes: string;
    readonly appointmentOutcome: string;
    readonly appointmentReason: string;
    readonly appointmentStatusLabels: Readonly<Record<string, string>>;
    readonly appointmentTimezone: string;
    readonly archiveParty: string;
    readonly archiveReason: string;
    readonly assigneeMembershipId: string;
    readonly assignedTo: string;
    readonly birthDate: string;
    readonly cancelTask: string;
    readonly channelKey: string;
    readonly complete: string;
    readonly consentSource: string;
    readonly consentStatus: string;
    readonly contactDetails: string;
    readonly contactTypeLabels: Readonly<Record<string, string>>;
    readonly countryCode: string;
    readonly convert: string;
    readonly convertDescription: string;
    readonly due: string;
    readonly activityBody: string;
    readonly activitySubject: string;
    readonly currencyCode: string;
    readonly dealId: string;
    readonly dealTypeKey: string;
    readonly description: string;
    readonly displayName: string;
    readonly doNotContact: string;
    readonly effectiveFrom: string;
    readonly effectiveTo: string;
    readonly emptyDescription: string;
    readonly emptyHeading: string;
    readonly heading: string;
    readonly familyName: string;
    readonly givenName: string;
    readonly identifierReason: string;
    readonly identifierType: string;
    readonly identifierValue: string;
    readonly isPreferred: string;
    readonly isPrimary: string;
    readonly jurisdiction: string;
    readonly leadCount: (count: number) => string;
    readonly leadId: string;
    readonly leadSummary: string;
    readonly legalEntityId: string;
    readonly legalName: string;
    readonly line1: string;
    readonly line2: string;
    readonly locationId: string;
    readonly locality: string;
    readonly lostReason: string;
    readonly newLead: string;
    readonly newParty: string;
    readonly nextAction: string;
    readonly nextActionAt: string;
    readonly noTimeline: string;
    readonly noAddresses: string;
    readonly noContacts: string;
    readonly noIdentifiers: string;
    readonly noPreferences: string;
    readonly noRelationships: string;
    readonly organization: string;
    readonly ownerMembershipId: string;
    readonly overdue: string;
    readonly partyDetails: string;
    readonly partyIdentifiers: string;
    readonly partyPreferences: string;
    readonly partyCount: (count: number) => string;
    readonly partyId: string;
    readonly partyProfile: string;
    readonly partyType: string;
    readonly partyStatusLabels: Readonly<Record<string, string>>;
    readonly person: string;
    readonly postalCode: string;
    readonly preferredLocale: string;
    readonly preferredName: string;
    readonly priority: string;
    readonly prospectPartyId: string;
    readonly reasonRequired: string;
    readonly relationRequired: string;
    readonly region: string;
    readonly registrationName: string;
    readonly relatedPartyId: string;
    readonly relationshipType: string;
    readonly relationships: string;
    readonly replaceIdentifier: string;
    readonly revealIdentifier: string;
    readonly revealedIdentifier: string;
    readonly searchLabel: string;
    readonly stateLabels: Readonly<Record<string, string>>;
    readonly summary: string;
    readonly source: string;
    readonly startsAt: string;
    readonly setPreference: string;
    readonly endsAt: string;
    readonly taskEmpty: string;
    readonly taskCancelReason: string;
    readonly taskHeading: string;
    readonly timeline: string;
    readonly timezone: string;
    readonly title: string;
    readonly today: string;
    readonly transition: string;
    readonly transitionTarget: string;
    readonly updateAppointment: string;
    readonly updateProfile: string;
    readonly workflow: string;
  };
  readonly deals: {
    readonly addFinance: string;
    readonly addInventory: string;
    readonly addLineItem: string;
    readonly addParticipant: string;
    readonly addPayment: string;
    readonly addTradeIn: string;
    readonly allowance: string;
    readonly amount: string;
    readonly applicantPartyId: string;
    readonly approvalExpiresAt: string;
    readonly approvedAmount: string;
    readonly awaitingLender: string;
    readonly correctionReason: string;
    readonly createInventorySeparately: string;
    readonly currency: string;
    readonly correctPayment: string;
    readonly correctionAmount: string;
    readonly correctionType: string;
    readonly configuredOptionUnavailable: string;
    readonly addCondition: string;
    readonly changeFinanceStatus: string;
    readonly conditionDescription: string;
    readonly conditionDueAt: string;
    readonly conditionKey: string;
    readonly conditionRequired: string;
    readonly conditionSatisfiedAt: string;
    readonly conditions: string;
    readonly createDeal: string;
    readonly dealCount: (count: number) => string;
    readonly dealType: string;
    readonly dealNumber: string;
    readonly emptyDescription: string;
    readonly emptyHeading: string;
    readonly editTradeIn: string;
    readonly financeDisclaimer: string;
    readonly financeHeading: string;
    readonly financeNotes: string;
    readonly fundedAt: string;
    readonly fundingReference: string;
    readonly heading: string;
    readonly inventory: string;
    readonly inventoryAmount: string;
    readonly inventoryLinkStatusLabels: Readonly<Record<string, string>>;
    readonly inventoryRole: string;
    readonly inventoryStatusLabels: Readonly<Record<string, string>>;
    readonly inventoryUnitId: string;
    readonly lenderPartyId: string;
    readonly lenderReportedRate: string;
    readonly lenderReportedTerm: string;
    readonly lien: string;
    readonly lineItems: string;
    readonly lineItemKey: string;
    readonly lineItemLabel: string;
    readonly lineItemType: string;
    readonly moneyHeading: string;
    readonly newDeal: string;
    readonly noFinance: string;
    readonly noInventory: string;
    readonly noLineItems: string;
    readonly noPayments: string;
    readonly noParticipants: string;
    readonly noTradeIns: string;
    readonly notes: string;
    readonly occurredAt: string;
    readonly openDeal: string;
    readonly participants: string;
    readonly participantPartyId: string;
    readonly participantPrimary: string;
    readonly participantRole: string;
    readonly participantStatusLabels: Readonly<Record<string, string>>;
    readonly paymentMethod: string;
    readonly paymentNotes: string;
    readonly paymentProof: string;
    readonly paymentReference: string;
    readonly recordedBy: string;
    readonly lastUpdatedBy: string;
    readonly correctsPayment: string;
    readonly payoff: string;
    readonly paymentStatus: Readonly<Record<string, string>>;
    readonly refund: string;
    readonly recordFinance: string;
    readonly recordPayment: string;
    readonly confirmTradeInInventory: string;
    readonly releaseInventory: string;
    readonly releaseParticipant: string;
    readonly requestedAmount: string;
    readonly resultingInventoryUnitId: string;
    readonly review: string;
    readonly reverse: string;
    readonly settle: string;
    readonly settledAt: string;
    readonly statusReason: string;
    readonly statusUnavailable: string;
    readonly submittedAt: string;
    readonly supportingFileId: string;
    readonly sortOrder: string;
    readonly sourceKey: string;
    readonly sourceReference: string;
    readonly step: string;
    readonly stateLabels: Readonly<Record<string, string>>;
    readonly summary: string;
    readonly tradeMake: string;
    readonly tradeModel: string;
    readonly tradeVin: string;
    readonly tradeYear: string;
    readonly transactionType: string;
    readonly transactionTypeLabels: Readonly<Record<string, string>>;
    readonly transitionReasonRequired: string;
    readonly tradeInHeading: string;
    readonly tradeInStatusLabels: Readonly<Record<string, string>>;
    readonly updatedAt: string;
    readonly updateCondition: string;
    readonly updateFinance: string;
    readonly customerAcceptedAt: string;
    readonly updateLineItem: string;
    readonly quantity: string;
    readonly taxClassification: string;
    readonly paymentTiming: string;
    readonly unitAmount: string;
    readonly version: string;
    readonly workflow: string;
  };
}

const en: M3Messages = {
  common: {
    appName: "Vynlo",
    appointments: "Appointments",
    attention: "Needs attention",
    back: "Back",
    cancel: "Cancel",
    close: "Close",
    continue: "Continue",
    create: "Create",
    deals: "Deals",
    details: "Details",
    environment: "Development",
    errorDescription:
      "Your input is preserved. Refresh the latest record or retry with the correlation ID shown.",
    errorHeading: "The change was not saved",
    leads: "Leads",
    loading: "Loading…",
    localeLabel: "Language",
    localeNames: { en: "English", fr: "Français" },
    navigationLabel: "Dealership operations",
    offline: "Offline — finalizing and writes are disabled.",
    parties: "Parties",
    retry: "Retry",
    required: "Required",
    save: "Save",
    saved: "Saved",
    saving: "Saving…",
    skipToContent: "Skip to content",
    status: "Status",
    tasks: "Tasks",
    view: "View",
    workspaceLabel: "Workspace",
  },
  crm: {
    addActivity: "Add activity",
    addAddress: "Add address",
    addAppointment: "Schedule appointment",
    addContact: "Add contact",
    addRelationship: "Add relationship",
    addTask: "Add task",
    addressType: "Address type",
    addresses: "Addresses",
    allowed: "Allowed",
    appointmentEmpty: "No appointments in this window.",
    appointmentHeading: "Appointments",
    appointmentNotes: "Appointment notes",
    appointmentOutcome: "Appointment outcome",
    appointmentReason: "Reason for cancellation or no-show",
    appointmentStatusLabels: {
      cancelled: "Cancelled",
      completed: "Completed",
      no_show: "No-show",
      scheduled: "Scheduled",
    },
    appointmentTimezone: "Times shown with their recorded timezone",
    archiveParty: "Archive party",
    archiveReason: "Reason for archiving",
    assigneeMembershipId: "Assignee membership ID",
    assignedTo: "Assigned to",
    birthDate: "Birth date",
    cancelTask: "Cancel task",
    channelKey: "Communication channel",
    complete: "Complete",
    consentSource: "Consent source",
    consentStatus: "Consent status",
    contactDetails: "Contact details",
    contactTypeLabels: { email: "Email", phone: "Phone" },
    countryCode: "Country code",
    convert: "Convert to deal",
    convertDescription:
      "The qualified lead, party and timeline stay linked to one configured deal.",
    due: "Due",
    activityBody: "Activity note",
    activitySubject: "Activity subject",
    currencyCode: "Currency code",
    dealId: "Deal ID",
    dealTypeKey: "Deal type key",
    description: "Description",
    displayName: "Display name",
    doNotContact: "Do not contact",
    effectiveFrom: "Effective from",
    effectiveTo: "Effective to",
    emptyDescription:
      "Capture an enquiry, assign an owner and make the next action explicit.",
    emptyHeading: "No leads match this view",
    heading: "Customer follow-up",
    familyName: "Family name",
    givenName: "Given name",
    identifierReason: "Reason for restricted identifier access",
    identifierType: "Identifier type",
    identifierValue: "Identifier value",
    isPreferred: "Preferred contact",
    isPrimary: "Primary",
    jurisdiction: "Jurisdiction",
    leadCount: (count) => `${count} ${count === 1 ? "lead" : "leads"}`,
    leadId: "Lead ID",
    leadSummary: "Lead summary",
    legalEntityId: "Legal entity ID",
    legalName: "Legal name",
    line1: "Address line 1",
    line2: "Address line 2",
    locationId: "Location ID",
    locality: "City or locality",
    lostReason: "Reason for closing lost",
    newLead: "New lead",
    newParty: "New party",
    nextAction: "Next action",
    nextActionAt: "Next action date and time",
    noTimeline: "No activity has been recorded yet.",
    noAddresses: "No addresses have been recorded.",
    noContacts: "No contact details have been recorded.",
    noIdentifiers: "No restricted identifiers have been recorded.",
    noPreferences: "No communication preferences have been recorded.",
    noRelationships: "No relationships have been recorded.",
    organization: "Organization",
    ownerMembershipId: "Owner membership ID",
    overdue: "Overdue",
    partyDetails: "Profile and contact details",
    partyIdentifiers: "Restricted identifiers",
    partyPreferences: "Communication preferences",
    partyCount: (count) => `${count} ${count === 1 ? "party" : "parties"}`,
    partyId: "Party ID",
    partyProfile: "Typed profile",
    partyType: "Party type",
    partyStatusLabels: { active: "Active", archived: "Archived" },
    person: "Person",
    postalCode: "Postal code",
    preferredLocale: "Preferred language",
    preferredName: "Preferred name",
    priority: "Priority",
    prospectPartyId: "Prospect party ID",
    reasonRequired: "A reason is required before closing this lead as lost.",
    relationRequired: "Link this record to at least one party, lead, or deal.",
    region: "Province, state or region",
    registrationName: "Registration name",
    relatedPartyId: "Related party ID",
    relationshipType: "Relationship type",
    relationships: "Relationships",
    replaceIdentifier: "Replace restricted identifier",
    revealIdentifier: "Reveal restricted identifier",
    revealedIdentifier: "Revealed identifier",
    searchLabel: "Search leads or parties",
    stateLabels: {
      appointment: "Appointment",
      contacted: "Contacted",
      converted: "Converted",
      lost: "Lost",
      new: "New",
      qualified: "Qualified",
    },
    source: "Source",
    startsAt: "Starts at",
    setPreference: "Set communication preference",
    endsAt: "Ends at",
    summary:
      "A quiet queue for the next customer action, not another dashboard.",
    taskEmpty: "No open tasks match this view.",
    taskCancelReason: "Reason for cancelling the task",
    taskHeading: "Tasks",
    timeline: "Timeline",
    timezone: "Timezone",
    title: "Title",
    today: "Today",
    transition: "Move lead",
    transitionTarget: "Next state",
    updateAppointment: "Update appointment",
    updateProfile: "Update typed profile",
    workflow: "Lead workflow",
  },
  deals: {
    addFinance: "Record lender application",
    addInventory: "Add inventory unit",
    addLineItem: "Add line item",
    addParticipant: "Add participant",
    addPayment: "Record one-time transaction",
    addTradeIn: "Add trade-in",
    allowance: "Trade-in allowance",
    amount: "Amount",
    applicantPartyId: "Applicant party ID",
    approvalExpiresAt: "Approval expires at",
    approvedAmount: "Approved amount",
    awaitingLender: "Awaiting lender",
    correctionReason: "Reason for correction",
    correctPayment: "Record correction",
    correctionAmount: "Correction amount",
    correctionType: "Correction type",
    configuredOptionUnavailable: "Configured option unavailable",
    addCondition: "Add lender condition",
    changeFinanceStatus: "Change finance status",
    conditionDescription: "Condition description",
    conditionDueAt: "Condition due at",
    conditionKey: "Condition key",
    conditionRequired: "Required condition",
    conditionSatisfiedAt: "Satisfied at",
    conditions: "Lender conditions",
    createDeal: "Create deal",
    createInventorySeparately: "Confirm resulting inventory separately",
    currency: "Currency",
    dealCount: (count) => `${count} ${count === 1 ? "deal" : "deals"}`,
    dealNumber: "Deal number",
    dealType: "Deal type",
    emptyDescription:
      "Start from a configured deal type; its roles, workflow and steps stay pinned.",
    emptyHeading: "No deals match this view",
    editTradeIn: "Edit trade-in",
    financeDisclaimer:
      "Lender-reported terms only. Vynlo does not calculate or service a repayment schedule.",
    financeHeading: "External finance",
    financeNotes: "Finance notes",
    fundedAt: "Funded at",
    fundingReference: "Funding reference",
    heading: "Deal workspace",
    inventory: "Inventory and trade-ins",
    inventoryAmount: "Inventory amount",
    inventoryLinkStatusLabels: {
      active: "Linked",
      released: "Released",
    },
    inventoryRole: "Inventory role",
    inventoryStatusLabels: {
      active: "Active",
      archived: "Archived",
      closed: "Closed",
      draft: "Draft",
      pending: "Pending",
    },
    inventoryUnitId: "Inventory unit ID",
    lenderPartyId: "Lender party ID",
    lenderReportedRate: "Lender-reported annual rate",
    lenderReportedTerm: "Lender-reported term",
    lien: "Declared lien",
    lineItems: "Exact line items",
    lineItemKey: "Line-item key",
    lineItemLabel: "Line-item label",
    lineItemType: "Line-item type",
    moneyHeading: "One-time money ledger",
    newDeal: "New deal",
    noFinance: "No lender application has been recorded.",
    noInventory: "No inventory units are linked to this deal.",
    noLineItems: "No line items are recorded on this deal.",
    noPayments: "No one-time transactions have been recorded.",
    noParticipants: "No participants are linked to this deal.",
    noTradeIns: "No trade-ins have been recorded.",
    notes: "Notes",
    occurredAt: "Occurred at",
    openDeal: "Open deal",
    participants: "Participants",
    participantPartyId: "Participant party ID",
    participantPrimary: "Primary participant",
    participantRole: "Participant role",
    participantStatusLabels: {
      active: "Active",
      released: "Released",
    },
    paymentMethod: "Payment method",
    paymentNotes: "Payment notes",
    paymentProof: "Proof file ID",
    paymentReference: "Reference",
    recordedBy: "Recorded by user",
    lastUpdatedBy: "Last updated by user",
    correctsPayment: "Corrects transaction",
    payoff: "Payoff amount",
    paymentStatus: {
      cancelled: "Cancelled",
      recorded: "Recorded",
      settled: "Settled",
    },
    refund: "Refund",
    recordFinance: "Record lender application",
    recordPayment: "Record transaction",
    confirmTradeInInventory: "Confirm resulting inventory unit",
    releaseInventory: "Release inventory unit",
    releaseParticipant: "Release participant",
    requestedAmount: "Requested amount",
    resultingInventoryUnitId: "Resulting inventory unit ID",
    review: "Review",
    reverse: "Reverse remainder",
    settle: "Settle",
    settledAt: "Settled at",
    statusReason: "Status reason",
    statusUnavailable: "Status unavailable",
    submittedAt: "Submitted at",
    supportingFileId: "Supporting file ID",
    sortOrder: "Sort order",
    sourceKey: "Source key",
    sourceReference: "Source reference",
    step: "Step",
    stateLabels: {
      additional_information_required: "Additional information required",
      approved: "Approved",
      awaiting_customer: "Awaiting customer",
      awaiting_lender: "Awaiting lender",
      cancelled: "Cancelled",
      completed: "Completed",
      conditionally_approved: "Conditionally approved",
      customer_declined: "Customer declined",
      declined: "Declined",
      draft: "Draft",
      expired: "Expired",
      funded: "Funded",
      preparing: "Preparing",
      ready_for_delivery: "Ready for delivery",
      submitted: "Submitted",
    },
    summary:
      "Participants, inventory, line items and money stay visible through every configured step.",
    tradeMake: "Trade-in make",
    tradeModel: "Trade-in model",
    tradeVin: "Trade-in VIN",
    tradeYear: "Trade-in year",
    transactionType: "Transaction type",
    transactionTypeLabels: {
      balance_received: "Balance received",
      deposit: "Deposit",
      lender_proceeds: "Lender proceeds",
      other: "Other",
      receipt: "Receipt",
      trade_in_credit: "Trade-in credit",
    },
    transitionReasonRequired:
      "A reason is required for this workflow transition.",
    tradeInHeading: "Trade-in",
    tradeInStatusLabels: {
      active: "Active",
      cancelled: "Cancelled",
      confirmed: "Confirmed",
    },
    updatedAt: "Updated",
    updateCondition: "Replace or satisfy condition",
    updateFinance: "Update finance application",
    customerAcceptedAt: "Customer accepted at",
    updateLineItem: "Update line item",
    quantity: "Quantity",
    taxClassification: "Tax classification",
    paymentTiming: "Payment timing",
    unitAmount: "Unit amount",
    version: "Version",
    workflow: "Deal workflow",
  },
};

const fr: M3Messages = {
  common: {
    appName: "Vynlo",
    appointments: "Rendez-vous",
    attention: "À traiter",
    back: "Retour",
    cancel: "Annuler",
    close: "Fermer",
    continue: "Continuer",
    create: "Créer",
    deals: "Dossiers",
    details: "Détails",
    environment: "Développement",
    errorDescription:
      "Vos données sont conservées. Actualisez la fiche ou réessayez avec l’identifiant de corrélation affiché.",
    errorHeading: "La modification n’a pas été enregistrée",
    leads: "Prospects",
    loading: "Chargement…",
    localeLabel: "Langue",
    localeNames: { en: "Anglais", fr: "Français" },
    navigationLabel: "Opérations de la concession",
    offline: "Hors ligne — les écritures et la finalisation sont désactivées.",
    parties: "Clients",
    retry: "Réessayer",
    required: "Obligatoire",
    save: "Enregistrer",
    saved: "Enregistré",
    saving: "Enregistrement…",
    skipToContent: "Aller au contenu",
    status: "État",
    tasks: "Tâches",
    view: "Voir",
    workspaceLabel: "Espace de travail",
  },
  crm: {
    addActivity: "Ajouter une activité",
    addAddress: "Ajouter une adresse",
    addAppointment: "Planifier un rendez-vous",
    addContact: "Ajouter une coordonnée",
    addRelationship: "Ajouter une relation",
    addTask: "Ajouter une tâche",
    addressType: "Type d’adresse",
    addresses: "Adresses",
    allowed: "Autorisé",
    appointmentEmpty: "Aucun rendez-vous dans cette période.",
    appointmentHeading: "Rendez-vous",
    appointmentNotes: "Notes du rendez-vous",
    appointmentOutcome: "Résultat du rendez-vous",
    appointmentReason: "Motif de l’annulation ou de l’absence",
    appointmentStatusLabels: {
      cancelled: "Annulé",
      completed: "Terminé",
      no_show: "Absent",
      scheduled: "Planifié",
    },
    appointmentTimezone: "Les heures conservent leur fuseau horaire enregistré",
    archiveParty: "Archiver le client",
    archiveReason: "Motif de l’archivage",
    assigneeMembershipId: "ID du membre responsable",
    assignedTo: "Responsable",
    birthDate: "Date de naissance",
    cancelTask: "Annuler la tâche",
    channelKey: "Canal de communication",
    complete: "Terminer",
    consentSource: "Source du consentement",
    consentStatus: "État du consentement",
    contactDetails: "Coordonnées",
    contactTypeLabels: { email: "Courriel", phone: "Téléphone" },
    countryCode: "Code de pays",
    convert: "Convertir en dossier",
    convertDescription:
      "Le prospect qualifié, le client et l’historique restent liés à un seul dossier configuré.",
    due: "Échéance",
    activityBody: "Note d’activité",
    activitySubject: "Objet de l’activité",
    currencyCode: "Code de devise",
    dealId: "ID du dossier",
    dealTypeKey: "Clé du type de dossier",
    description: "Description",
    displayName: "Nom affiché",
    doNotContact: "Ne pas contacter",
    effectiveFrom: "En vigueur à partir du",
    effectiveTo: "En vigueur jusqu’au",
    emptyDescription:
      "Saisissez une demande, assignez un responsable et précisez la prochaine action.",
    emptyHeading: "Aucun prospect dans cette vue",
    heading: "Suivi des clients",
    familyName: "Nom de famille",
    givenName: "Prénom",
    identifierReason: "Motif d’accès à l’identifiant restreint",
    identifierType: "Type d’identifiant",
    identifierValue: "Valeur de l’identifiant",
    isPreferred: "Coordonnée préférée",
    isPrimary: "Principale",
    jurisdiction: "Juridiction",
    leadCount: (count) => `${count} prospect${count === 1 ? "" : "s"}`,
    leadId: "ID du prospect",
    leadSummary: "Résumé du prospect",
    legalEntityId: "ID de l’entité juridique",
    legalName: "Nom légal",
    line1: "Adresse, ligne 1",
    line2: "Adresse, ligne 2",
    locationId: "ID de l’emplacement",
    locality: "Ville ou localité",
    lostReason: "Motif de fermeture sans vente",
    newLead: "Nouveau prospect",
    newParty: "Nouveau client",
    nextAction: "Prochaine action",
    nextActionAt: "Date et heure de la prochaine action",
    noTimeline: "Aucune activité n’a encore été consignée.",
    noAddresses: "Aucune adresse n’a été consignée.",
    noContacts: "Aucune coordonnée n’a été consignée.",
    noIdentifiers: "Aucun identifiant restreint n’a été consigné.",
    noPreferences: "Aucune préférence de communication n’a été consignée.",
    noRelationships: "Aucune relation n’a été consignée.",
    organization: "Organisation",
    ownerMembershipId: "ID du membre responsable",
    overdue: "En retard",
    partyDetails: "Profil et coordonnées",
    partyIdentifiers: "Identifiants restreints",
    partyPreferences: "Préférences de communication",
    partyCount: (count) => `${count} client${count === 1 ? "" : "s"}`,
    partyId: "ID du client",
    partyProfile: "Profil typé",
    partyType: "Type de client",
    partyStatusLabels: { active: "Actif", archived: "Archivé" },
    person: "Personne",
    postalCode: "Code postal",
    preferredLocale: "Langue préférée",
    preferredName: "Prénom usuel",
    priority: "Priorité",
    prospectPartyId: "ID du client prospect",
    reasonRequired:
      "Un motif est requis avant de fermer ce prospect comme perdu.",
    relationRequired:
      "Liez cet élément à au moins un client, prospect ou dossier.",
    region: "Province, état ou région",
    registrationName: "Nom d’immatriculation",
    relatedPartyId: "ID du client lié",
    relationshipType: "Type de relation",
    relationships: "Relations",
    replaceIdentifier: "Remplacer un identifiant restreint",
    revealIdentifier: "Révéler l’identifiant restreint",
    revealedIdentifier: "Identifiant révélé",
    searchLabel: "Rechercher un prospect ou un client",
    stateLabels: {
      appointment: "Rendez-vous",
      contacted: "Contacté",
      converted: "Converti",
      lost: "Perdu",
      new: "Nouveau",
      qualified: "Qualifié",
    },
    source: "Source",
    startsAt: "Début",
    setPreference: "Définir une préférence de communication",
    endsAt: "Fin",
    summary:
      "Une file de suivi claire pour la prochaine action, sans tableau de bord superflu.",
    taskEmpty: "Aucune tâche ouverte dans cette vue.",
    taskCancelReason: "Motif d’annulation de la tâche",
    taskHeading: "Tâches",
    timeline: "Historique",
    timezone: "Fuseau horaire",
    title: "Titre",
    today: "Aujourd’hui",
    transition: "Faire avancer le prospect",
    transitionTarget: "Prochain état",
    updateAppointment: "Mettre à jour le rendez-vous",
    updateProfile: "Mettre à jour le profil typé",
    workflow: "Parcours du prospect",
  },
  deals: {
    addFinance: "Consigner une demande au prêteur",
    addInventory: "Ajouter un véhicule d’inventaire",
    addLineItem: "Ajouter une ligne",
    addParticipant: "Ajouter un participant",
    addPayment: "Consigner une transaction ponctuelle",
    addTradeIn: "Ajouter un échange",
    allowance: "Valeur accordée pour l’échange",
    amount: "Montant",
    applicantPartyId: "ID du client demandeur",
    approvalExpiresAt: "Expiration de l’approbation",
    approvedAmount: "Montant approuvé",
    awaitingLender: "En attente du prêteur",
    correctionReason: "Motif de correction",
    correctPayment: "Consigner la correction",
    correctionAmount: "Montant de la correction",
    correctionType: "Type de correction",
    configuredOptionUnavailable: "Option configurée indisponible",
    addCondition: "Ajouter une condition du prêteur",
    changeFinanceStatus: "Modifier l’état du financement",
    conditionDescription: "Description de la condition",
    conditionDueAt: "Échéance de la condition",
    conditionKey: "Clé de la condition",
    conditionRequired: "Condition obligatoire",
    conditionSatisfiedAt: "Satisfaite le",
    conditions: "Conditions du prêteur",
    createDeal: "Créer le dossier",
    createInventorySeparately: "Confirmer séparément la création en inventaire",
    currency: "Devise",
    dealCount: (count) => `${count} dossier${count === 1 ? "" : "s"}`,
    dealNumber: "Numéro du dossier",
    dealType: "Type de dossier",
    emptyDescription:
      "Commencez avec un type configuré; ses rôles, son parcours et ses étapes restent figés.",
    emptyHeading: "Aucun dossier dans cette vue",
    editTradeIn: "Modifier l’échange",
    financeDisclaimer:
      "Conditions déclarées par le prêteur seulement. Vynlo ne calcule ni ne gère un calendrier de remboursement.",
    financeHeading: "Financement externe",
    financeNotes: "Notes de financement",
    fundedAt: "Financé le",
    fundingReference: "Référence du financement",
    heading: "Espace du dossier",
    inventory: "Inventaire et échanges",
    inventoryAmount: "Montant d’inventaire",
    inventoryLinkStatusLabels: {
      active: "Lié",
      released: "Libéré",
    },
    inventoryRole: "Rôle du véhicule",
    inventoryStatusLabels: {
      active: "Actif",
      archived: "Archivé",
      closed: "Fermé",
      draft: "Brouillon",
      pending: "En attente",
    },
    inventoryUnitId: "ID du véhicule en inventaire",
    lenderPartyId: "ID du prêteur",
    lenderReportedRate: "Taux annuel déclaré par le prêteur",
    lenderReportedTerm: "Durée déclarée par le prêteur",
    lien: "Sûreté déclarée",
    lineItems: "Lignes exactes",
    lineItemKey: "Clé de ligne",
    lineItemLabel: "Libellé de la ligne",
    lineItemType: "Type de ligne",
    moneyHeading: "Registre des transactions ponctuelles",
    newDeal: "Nouveau dossier",
    noFinance: "Aucune demande au prêteur n’a été consignée.",
    noInventory: "Aucun véhicule d’inventaire n’est lié à ce dossier.",
    noLineItems: "Aucune ligne n’est consignée dans ce dossier.",
    noPayments: "Aucune transaction ponctuelle n’a été consignée.",
    noParticipants: "Aucun participant n’est lié à ce dossier.",
    noTradeIns: "Aucun échange n’a été consigné.",
    notes: "Notes",
    occurredAt: "Date de la transaction",
    openDeal: "Ouvrir le dossier",
    participants: "Participants",
    participantPartyId: "ID du client participant",
    participantPrimary: "Participant principal",
    participantRole: "Rôle du participant",
    participantStatusLabels: {
      active: "Actif",
      released: "Libéré",
    },
    paymentMethod: "Mode de paiement",
    paymentNotes: "Notes de paiement",
    paymentProof: "ID du fichier justificatif",
    paymentReference: "Référence",
    recordedBy: "Consignée par l’utilisateur",
    lastUpdatedBy: "Dernière mise à jour par l’utilisateur",
    correctsPayment: "Corrige la transaction",
    payoff: "Montant de quittance",
    paymentStatus: {
      cancelled: "Annulée",
      recorded: "Consignée",
      settled: "Réglée",
    },
    refund: "Rembourser",
    recordFinance: "Consigner la demande au prêteur",
    recordPayment: "Consigner la transaction",
    confirmTradeInInventory: "Confirmer le véhicule d’inventaire résultant",
    releaseInventory: "Libérer le véhicule d’inventaire",
    releaseParticipant: "Libérer le participant",
    requestedAmount: "Montant demandé",
    resultingInventoryUnitId: "ID du véhicule d’inventaire résultant",
    review: "Vérification",
    reverse: "Contrepasser le solde",
    settle: "Régler",
    settledAt: "Réglée le",
    statusReason: "Motif de l’état",
    statusUnavailable: "État indisponible",
    submittedAt: "Soumise le",
    supportingFileId: "ID du fichier justificatif",
    sortOrder: "Ordre de tri",
    sourceKey: "Clé source",
    sourceReference: "Référence source",
    step: "Étape",
    stateLabels: {
      additional_information_required: "Renseignements supplémentaires requis",
      approved: "Approuvé",
      awaiting_customer: "En attente du client",
      awaiting_lender: "En attente du prêteur",
      cancelled: "Annulé",
      completed: "Terminé",
      conditionally_approved: "Approuvé sous conditions",
      customer_declined: "Refusé par le client",
      declined: "Refusé",
      draft: "Brouillon",
      expired: "Expiré",
      funded: "Financé",
      preparing: "En préparation",
      ready_for_delivery: "Prêt pour la livraison",
      submitted: "Soumis",
    },
    summary:
      "Les participants, véhicules, lignes et montants restent visibles à chaque étape configurée.",
    tradeMake: "Marque du véhicule échangé",
    tradeModel: "Modèle du véhicule échangé",
    tradeVin: "NIV du véhicule échangé",
    tradeYear: "Année du véhicule échangé",
    transactionType: "Type de transaction",
    transactionTypeLabels: {
      balance_received: "Solde reçu",
      deposit: "Dépôt",
      lender_proceeds: "Fonds du prêteur",
      other: "Autre",
      receipt: "Encaissement",
      trade_in_credit: "Crédit d’échange",
    },
    transitionReasonRequired:
      "Un motif est requis pour cette transition du parcours.",
    tradeInHeading: "Échange",
    tradeInStatusLabels: {
      active: "Actif",
      cancelled: "Annulé",
      confirmed: "Confirmé",
    },
    updatedAt: "Mis à jour",
    updateCondition: "Remplacer ou satisfaire la condition",
    updateFinance: "Mettre à jour la demande de financement",
    customerAcceptedAt: "Acceptée par le client le",
    updateLineItem: "Mettre à jour la ligne",
    quantity: "Quantité",
    taxClassification: "Classification fiscale",
    paymentTiming: "Moment du paiement",
    unitAmount: "Montant unitaire",
    version: "Version",
    workflow: "Parcours du dossier",
  },
};

export const m3Messages: Readonly<Record<Locale, M3Messages>> = Object.freeze({
  en: Object.freeze(en),
  fr: Object.freeze(fr),
});
