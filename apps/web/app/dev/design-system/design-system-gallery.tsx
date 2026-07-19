"use client";

import type { ReactNode } from "react";
import {
  AlertCircle,
  Boxes,
  CheckCircle2,
  ChevronDown,
  FileText,
  Info,
  Menu,
  Settings2,
  Users,
} from "lucide-react";
import {
  Alert,
  AlertDescription,
  AlertTitle,
} from "@vynlo/ui-web/components/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@vynlo/ui-web/components/alert-dialog";
import { Badge } from "@vynlo/ui-web/components/badge";
import {
  Breadcrumb,
  BreadcrumbEllipsis,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@vynlo/ui-web/components/breadcrumb";
import { Button } from "@vynlo/ui-web/components/button";
import { Checkbox } from "@vynlo/ui-web/components/checkbox";
import { Combobox } from "@vynlo/ui-web/components/combobox";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
} from "@vynlo/ui-web/components/command";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@vynlo/ui-web/components/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@vynlo/ui-web/components/dropdown-menu";
import {
  Drawer,
  DrawerClose,
  DrawerContent,
  DrawerDescription,
  DrawerFooter,
  DrawerHeader,
  DrawerTitle,
  DrawerTrigger,
} from "@vynlo/ui-web/components/drawer";
import {
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@vynlo/ui-web/components/field";
import { Input } from "@vynlo/ui-web/components/input";
import { Label } from "@vynlo/ui-web/components/label";
import {
  NativeSelect,
  NativeSelectOption,
} from "@vynlo/ui-web/components/native-select";
import {
  Pagination,
  PaginationContent,
  PaginationEllipsis,
  PaginationItem,
  PaginationLink,
  PaginationNext,
  PaginationPrevious,
} from "@vynlo/ui-web/components/pagination";
import {
  Popover,
  PopoverContent,
  PopoverDescription,
  PopoverHeader,
  PopoverTitle,
  PopoverTrigger,
} from "@vynlo/ui-web/components/popover";
import { Progress } from "@vynlo/ui-web/components/progress";
import {
  RadioGroup,
  RadioGroupItem,
} from "@vynlo/ui-web/components/radio-group";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@vynlo/ui-web/components/select";
import { ScrollArea } from "@vynlo/ui-web/components/scroll-area";
import { Separator } from "@vynlo/ui-web/components/separator";
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@vynlo/ui-web/components/sheet";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from "@vynlo/ui-web/components/sidebar";
import { Skeleton } from "@vynlo/ui-web/components/skeleton";
import { toast } from "@vynlo/ui-web/components/sonner";
import { Switch } from "@vynlo/ui-web/components/switch";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@vynlo/ui-web/components/table";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@vynlo/ui-web/components/tabs";
import { Textarea } from "@vynlo/ui-web/components/textarea";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@vynlo/ui-web/components/tooltip";
import { ThemeSwitcher } from "../../../components/theme-switcher";

type Locale = "en" | "fr";

const copy = {
  en: {
    actions: "Actions",
    choices: "Choices",
    close: "Close",
    description:
      "The shared visual contract for Vynlo controls, states, and responsive surfaces.",
    feedback: "Feedback and progress",
    fields: "Fields",
    foundation: "Foundation",
    gallery: "Development gallery",
    layers: "Layers",
    navigation: "Navigation and data",
    title: "Vynlo System UI",
  },
  fr: {
    actions: "Actions",
    choices: "Choix",
    close: "Fermer",
    description:
      "Le contrat visuel partagé pour les contrôles, les états et les surfaces adaptatives de Vynlo.",
    feedback: "Rétroaction et progression",
    fields: "Champs",
    foundation: "Fondations",
    gallery: "Galerie de développement",
    layers: "Calques",
    navigation: "Navigation et données",
    title: "Interface système Vynlo",
  },
} as const;

function GallerySection({
  children,
  description,
  title,
}: {
  children: ReactNode;
  description: string;
  title: string;
}) {
  return (
    <section className="rounded-2xl border bg-card p-4 text-card-foreground shadow-sm sm:p-6">
      <div className="mb-6 space-y-1">
        <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
        <p className="text-sm text-muted-foreground">{description}</p>
      </div>
      {children}
    </section>
  );
}

function StateLabel({ children }: { children: ReactNode }) {
  return (
    <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
      {children}
    </span>
  );
}

type GalleryState =
  | "default"
  | "hover"
  | "focus"
  | "active"
  | "disabled"
  | "loading"
  | "error"
  | "success";

type PrimitiveCoverage = {
  readonly composed?: readonly GalleryState[];
  readonly direct: readonly GalleryState[];
  readonly family: "actions" | "feedback" | "fields" | "layers" | "navigation";
  readonly primitive: string;
};

const galleryStates = [
  "default",
  "hover",
  "focus",
  "active",
  "disabled",
  "loading",
  "error",
  "success",
] as const satisfies readonly GalleryState[];

const primitiveCoverage: readonly PrimitiveCoverage[] = [
  {
    family: "actions",
    primitive: "Button",
    direct: galleryStates,
  },
  {
    family: "fields",
    primitive: "Field",
    direct: ["default", "disabled", "error"],
    composed: ["loading", "success"],
  },
  {
    family: "fields",
    primitive: "Label",
    direct: ["default", "disabled"],
  },
  {
    family: "fields",
    primitive: "Input",
    direct: ["default", "focus", "disabled", "loading", "error", "success"],
  },
  {
    family: "fields",
    primitive: "Textarea",
    direct: ["default", "focus", "disabled", "loading", "error", "success"],
  },
  {
    family: "fields",
    primitive: "NativeSelect",
    direct: ["default", "focus", "disabled", "loading", "error", "success"],
  },
  {
    family: "fields",
    primitive: "Select",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "fields",
    primitive: "Checkbox",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["error", "success"],
  },
  {
    family: "fields",
    primitive: "RadioGroup",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["error", "success"],
  },
  {
    family: "fields",
    primitive: "Switch",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["error", "success"],
  },
  {
    family: "feedback",
    primitive: "Alert",
    direct: ["default", "error"],
    composed: ["loading", "success"],
  },
  {
    family: "feedback",
    primitive: "Badge",
    direct: ["default", "error"],
    composed: ["loading", "success"],
  },
  {
    family: "feedback",
    primitive: "Skeleton",
    direct: ["default", "loading"],
  },
  {
    family: "feedback",
    primitive: "Progress",
    direct: ["default", "loading", "success"],
  },
  {
    family: "feedback",
    primitive: "Sonner",
    direct: ["default", "loading", "error", "success"],
  },
  {
    family: "feedback",
    primitive: "Tooltip",
    direct: ["default", "hover", "focus"],
  },
  {
    family: "layers",
    primitive: "Dialog",
    direct: ["default", "focus", "active"],
    composed: ["disabled", "loading", "error", "success"],
  },
  {
    family: "layers",
    primitive: "AlertDialog",
    direct: ["default", "focus", "active", "error"],
    composed: ["disabled", "loading", "success"],
  },
  {
    family: "layers",
    primitive: "Sheet",
    direct: ["default", "focus", "active"],
    composed: ["disabled", "loading", "error", "success"],
  },
  {
    family: "layers",
    primitive: "Drawer",
    direct: ["default", "focus", "active"],
    composed: ["disabled", "loading", "error", "success"],
  },
  {
    family: "layers",
    primitive: "Popover",
    direct: ["default", "hover", "focus", "active"],
    composed: ["disabled", "loading", "error", "success"],
  },
  {
    family: "layers",
    primitive: "DropdownMenu",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "navigation",
    primitive: "Tabs",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "navigation",
    primitive: "Sidebar",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "navigation",
    primitive: "Breadcrumb",
    direct: ["default", "hover", "focus", "active"],
  },
  {
    family: "navigation",
    primitive: "Table",
    direct: ["default"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "navigation",
    primitive: "Pagination",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error"],
  },
  {
    family: "navigation",
    primitive: "ScrollArea",
    direct: ["default", "hover", "focus", "active"],
  },
  {
    family: "navigation",
    primitive: "Command",
    direct: ["default", "hover", "focus", "active", "disabled"],
    composed: ["loading", "error", "success"],
  },
  {
    family: "navigation",
    primitive: "Combobox",
    direct: galleryStates,
  },
  {
    family: "navigation",
    primitive: "Separator",
    direct: ["default"],
  },
];

function PrimitiveStateMatrix({ locale }: { locale: Locale }) {
  const isFrench = locale === "fr";
  const stateLabels: Record<GalleryState, string> = isFrench
    ? {
        active: "Actif",
        default: "Défaut",
        disabled: "Désactivé",
        error: "Erreur",
        focus: "Ciblé",
        hover: "Survol",
        loading: "Chargement",
        success: "Succès",
      }
    : {
        active: "Active",
        default: "Default",
        disabled: "Disabled",
        error: "Error",
        focus: "Focus",
        hover: "Hover",
        loading: "Loading",
        success: "Success",
      };
  const familyLabels = isFrench
    ? {
        actions: "Actions",
        feedback: "Rétroaction",
        fields: "Champs",
        layers: "Calques",
        navigation: "Navigation",
      }
    : {
        actions: "Actions",
        feedback: "Feedback",
        fields: "Fields",
        layers: "Layers",
        navigation: "Navigation",
      };
  const directLabel = isFrench ? "Intégré" : "Built in";
  const composedLabel = isFrench ? "Composition" : "Compose";
  const unavailableLabel = isFrench ? "Sans objet" : "Not applicable";

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted-foreground">
        <span>
          <strong className="font-semibold text-foreground">●</strong>{" "}
          {directLabel}
        </span>
        <span>
          <strong className="font-semibold text-foreground">○</strong>{" "}
          {composedLabel}
        </span>
        <span>— {unavailableLabel}</span>
      </div>
      <div className="overflow-x-auto rounded-[var(--radius-panel)] border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{isFrench ? "Famille" : "Family"}</TableHead>
              <TableHead>{isFrench ? "Primitive" : "Primitive"}</TableHead>
              {galleryStates.map((state) => (
                <TableHead className="text-center" key={state}>
                  {stateLabels[state]}
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {primitiveCoverage.map((item) => (
              <TableRow key={item.primitive}>
                <TableCell className="text-xs text-muted-foreground">
                  {familyLabels[item.family]}
                </TableCell>
                <TableCell className="font-medium">{item.primitive}</TableCell>
                {galleryStates.map((state) => {
                  const direct = item.direct.includes(state);
                  const composed = item.composed?.includes(state) ?? false;
                  const label = direct
                    ? directLabel
                    : composed
                      ? composedLabel
                      : unavailableLabel;

                  return (
                    <TableCell className="text-center" key={state}>
                      <span aria-hidden="true">
                        {direct ? "●" : composed ? "○" : "—"}
                      </span>
                      <span className="sr-only">
                        {item.primitive}: {stateLabels[state]} — {label}
                      </span>
                    </TableCell>
                  );
                })}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <p className="text-xs leading-5 text-muted-foreground">
        {isFrench
          ? "Intégré signifie que la primitive possède l’état. Composition signifie que l’application ajoute cet état avec Field, Alert ou une autre primitive. Le sélecteur de thème ci-dessus permet de vérifier la même matrice en modes clair et sombre."
          : "Built in means the primitive owns the state. Compose means the application supplies it through Field, Alert, or another primitive. Use the theme switcher above to inspect the same matrix in light and dark modes."}
      </p>
    </div>
  );
}

export function DesignSystemGallery({ locale }: { locale: Locale }) {
  const text = copy[locale];
  const localized = (english: string, french: string) =>
    locale === "fr" ? french : english;

  return (
    <main className="min-h-screen bg-background text-foreground">
      <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur-xl">
        <div className="mx-auto flex min-h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold">{text.title}</p>
            <p className="truncate text-xs text-muted-foreground">
              {text.gallery}
            </p>
          </div>
          <ThemeSwitcher locale={locale} />
        </div>
      </header>

      <div className="mx-auto max-w-6xl space-y-6 px-4 py-8 sm:px-6 sm:py-12">
        <div className="max-w-3xl space-y-3">
          <Badge variant="secondary">UI-MIG-02</Badge>
          <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
            {text.title}
          </h1>
          <p className="text-base leading-7 text-muted-foreground">
            {text.description}
          </p>
        </div>

        <GallerySection
          description={localized("Semantic roles", "Rôles sémantiques")}
          title={text.foundation}
        >
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            {[
              ["Background", "bg-background"],
              ["Surface", "bg-card"],
              ["Primary", "bg-primary"],
              ["Muted", "bg-muted"],
              ["Destructive", "bg-destructive"],
            ].map(([label, color]) => (
              <div className="space-y-2" key={label}>
                <div className={`h-20 rounded-xl border ${color}`} />
                <p className="text-sm font-medium">{label}</p>
              </div>
            ))}
          </div>
        </GallerySection>

        <GallerySection
          description={localized(
            "Explicit state ownership for every approved shared primitive. Hover, focus, and active rows describe real interaction—not forced visual imitations.",
            "Propriété explicite des états pour chaque primitive partagée approuvée. Les lignes de survol, de ciblage et d’activation décrivent de vraies interactions, et non des imitations visuelles forcées.",
          )}
          title={localized(
            "Primitive state matrix",
            "Matrice d’états des primitives",
          )}
        >
          <PrimitiveStateMatrix locale={locale} />
        </GallerySection>

        <GallerySection
          description={localized(
            "Default, focus, disabled, loading, and destructive states",
            "États par défaut, ciblé, désactivé, chargement et destructif",
          )}
          title={text.actions}
        >
          <div className="grid gap-5 md:grid-cols-2">
            <div className="space-y-3">
              <StateLabel>{localized("Hierarchy", "Hiérarchie")}</StateLabel>
              <div className="flex flex-wrap gap-3">
                <Button className="min-h-11">
                  {localized("Primary", "Primaire")}
                </Button>
                <Button className="min-h-11" variant="secondary">
                  {localized("Secondary", "Secondaire")}
                </Button>
                <Button className="min-h-11" variant="outline">
                  {localized("Outline", "Contour")}
                </Button>
                <Button className="min-h-11" variant="ghost">
                  {localized("Ghost", "Discret")}
                </Button>
                <Button className="min-h-11" variant="destructive">
                  {localized("Delete", "Supprimer")}
                </Button>
              </div>
            </div>
            <div className="space-y-3">
              <StateLabel>
                {localized("Interaction and status", "Interaction et état")}
              </StateLabel>
              <div className="flex flex-wrap gap-3">
                <Button className="min-h-11" variant="outline">
                  {localized(
                    "Hover, focus, or press",
                    "Survoler, cibler ou appuyer",
                  )}
                </Button>
                <Button className="min-h-11" disabled>
                  {localized("Disabled", "Désactivé")}
                </Button>
                <Button
                  className="min-h-11"
                  status="loading"
                  statusLabel={localized(
                    "Saving in progress",
                    "Enregistrement en cours",
                  )}
                >
                  {localized("Loading", "Chargement")}
                </Button>
                <Button className="min-h-11" status="error">
                  {localized("Error", "Erreur")}
                </Button>
                <Button className="min-h-11" status="success">
                  {localized("Success", "Succès")}
                </Button>
              </div>
              <p className="text-xs leading-5 text-muted-foreground">
                {localized(
                  "Use the first live control to inspect genuine hover, focus, and active behavior.",
                  "Utilisez le premier contrôle pour vérifier les vrais comportements de survol, de ciblage et d’activation.",
                )}
              </p>
            </div>
          </div>
        </GallerySection>

        <GallerySection
          description={localized(
            "Labels, guidance, validation, and input selection",
            "Libellés, aide, validation et sélection",
          )}
          title={text.fields}
        >
          <FieldGroup className="grid gap-6 md:grid-cols-2">
            <div>
              <Label htmlFor="gallery-label-example">
                {localized("Standalone label", "Libellé autonome")}
              </Label>
              <Input
                id="gallery-label-example"
                placeholder={localized("Labeled input", "Champ avec libellé")}
              />
            </div>
            <Field>
              <FieldLabel htmlFor="gallery-name">
                {localized("Label", "Libellé")}
              </FieldLabel>
              <Input
                id="gallery-name"
                placeholder={localized("Placeholder", "Exemple")}
              />
              <FieldDescription>
                {localized("Supporting guidance", "Indication complémentaire")}
              </FieldDescription>
            </Field>
            <Field data-invalid="true">
              <FieldLabel htmlFor="gallery-error">
                {localized("Error", "Erreur")}
              </FieldLabel>
              <Input
                aria-describedby="gallery-error-message"
                aria-invalid="true"
                id="gallery-error"
                value={localized("Invalid", "Invalide")}
                readOnly
              />
              <FieldError id="gallery-error-message">
                {localized("Review this value", "Vérifiez cette valeur")}
              </FieldError>
            </Field>
            <Field>
              <FieldLabel htmlFor="gallery-select">
                {localized("Select", "Sélectionner")}
              </FieldLabel>
              <Select defaultValue="standard">
                <SelectTrigger className="min-h-11 w-full" id="gallery-select">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="standard">Standard</SelectItem>
                  <SelectItem value="compact">
                    {localized("Compact", "Compacte")}
                  </SelectItem>
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor="gallery-native-select">
                {localized("Native select", "Sélecteur natif")}
              </FieldLabel>
              <NativeSelect
                className="min-h-11 w-full"
                id="gallery-native-select"
              >
                <NativeSelectOption>
                  {localized("System", "Système")}
                </NativeSelectOption>
                <NativeSelectOption>
                  {localized("Manual", "Manuel")}
                </NativeSelectOption>
              </NativeSelect>
            </Field>
            <Field className="md:col-span-2">
              <FieldLabel htmlFor="gallery-note">Notes</FieldLabel>
              <Textarea
                className="min-h-24"
                id="gallery-note"
                placeholder={localized(
                  "Optional context",
                  "Contexte facultatif",
                )}
              />
            </Field>
          </FieldGroup>
        </GallerySection>

        <GallerySection
          description={localized(
            "Binary and exclusive controls",
            "Contrôles binaires et exclusifs",
          )}
          title={text.choices}
        >
          <div className="grid gap-6 md:grid-cols-3">
            <label className="flex min-h-11 items-center gap-3 text-sm font-medium">
              <Checkbox defaultChecked />
              {localized("Enabled", "Activé")}
            </label>
            <label className="flex min-h-11 items-center gap-3 text-sm font-medium">
              <Switch aria-label="Notifications" defaultChecked />
              Notifications
            </label>
            <RadioGroup defaultValue="automatic">
              <label className="flex min-h-11 items-center gap-3 text-sm font-medium">
                <RadioGroupItem value="automatic" />
                {localized("Automatic", "Automatique")}
              </label>
              <label className="flex min-h-11 items-center gap-3 text-sm font-medium">
                <RadioGroupItem value="manual" />
                {localized("Manual", "Manuel")}
              </label>
            </RadioGroup>
          </div>
        </GallerySection>

        <GallerySection
          description={localized(
            "Success, information, error, waiting, and loading",
            "Succès, information, erreur, attente et chargement",
          )}
          title={text.feedback}
        >
          <div className="space-y-5">
            <div className="flex flex-wrap gap-2">
              <Badge>
                <CheckCircle2 aria-hidden="true" />
                {localized("Success", "Succès")}
              </Badge>
              <Badge variant="secondary">
                {localized("Pending", "En attente")}
              </Badge>
              <Badge variant="outline">{localized("Neutral", "Neutre")}</Badge>
              <Badge variant="destructive">
                <AlertCircle aria-hidden="true" />
                {localized("Error", "Erreur")}
              </Badge>
            </div>
            <div className="grid gap-3 md:grid-cols-2">
              <Alert>
                <Info aria-hidden="true" />
                <AlertTitle>Information</AlertTitle>
                <AlertDescription>
                  {localized(
                    "Supporting context is concise and actionable.",
                    "Le contexte est concis et exploitable.",
                  )}
                </AlertDescription>
              </Alert>
              <Alert variant="destructive">
                <AlertCircle aria-hidden="true" />
                <AlertTitle>{localized("Error", "Erreur")}</AlertTitle>
                <AlertDescription>
                  {localized(
                    "Explain what happened and the next step.",
                    "Expliquez le problème et la prochaine étape.",
                  )}
                </AlertDescription>
              </Alert>
            </div>
            <div className="grid gap-5 md:grid-cols-2">
              <div className="space-y-2">
                <StateLabel>{localized("Progress", "Progression")}</StateLabel>
                <Progress
                  aria-label={localized("Progress", "Progression")}
                  value={64}
                />
              </div>
              <div className="space-y-2">
                <StateLabel>{localized("Loading", "Chargement")}</StateLabel>
                <div
                  className="space-y-2"
                  aria-label={localized("Loading", "Chargement")}
                >
                  <Skeleton className="h-4 w-2/3" />
                  <Skeleton className="h-4 w-full" />
                </div>
              </div>
            </div>
            <div
              className="flex flex-wrap items-center gap-3 rounded-xl border bg-muted/40 px-4 py-3"
              role="status"
            >
              <Badge variant="outline">Sonner</Badge>
              <p className="text-sm text-muted-foreground">
                {localized(
                  "Toasts use the global, theme-aware host.",
                  "Les notifications utilisent l’hôte global adapté au thème.",
                )}
              </p>
              <Button
                onClick={() =>
                  toast.success(
                    localized("Changes saved", "Modifications enregistrées"),
                  )
                }
                size="sm"
                variant="outline"
              >
                {localized("Preview toast", "Aperçu de notification")}
              </Button>
            </div>
          </div>
        </GallerySection>

        <GallerySection
          description={localized(
            "Responsive hierarchy, selection, and bounded data",
            "Hiérarchie adaptative, sélection et données délimitées",
          )}
          title={text.navigation}
        >
          <div className="space-y-6" id="gallery-navigation">
            <Breadcrumb
              aria-label={localized("Component path", "Chemin des composants")}
            >
              <BreadcrumbList>
                <BreadcrumbItem>
                  <BreadcrumbLink href="#gallery-navigation">
                    {localized("System", "Système")}
                  </BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                  <BreadcrumbEllipsis
                    label={localized("More levels", "Autres niveaux")}
                  />
                </BreadcrumbItem>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                  <BreadcrumbLink href="#gallery-navigation">
                    {localized("Components", "Composants")}
                  </BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
                <BreadcrumbItem>
                  <BreadcrumbPage>Navigation</BreadcrumbPage>
                </BreadcrumbItem>
              </BreadcrumbList>
            </Breadcrumb>

            <div className="grid gap-4 lg:grid-cols-[minmax(0,1.2fr)_minmax(16rem,0.8fr)]">
              <div className="min-w-0 space-y-4">
                <Tabs defaultValue="states">
                  <TabsList>
                    <TabsTrigger value="states">
                      {localized("States", "États")}
                    </TabsTrigger>
                    <TabsTrigger value="usage">
                      {localized("Usage", "Utilisation")}
                    </TabsTrigger>
                    <TabsTrigger disabled value="disabled">
                      {localized("Disabled", "Désactivé")}
                    </TabsTrigger>
                  </TabsList>
                  <TabsContent value="states">
                    <div className="mt-3 overflow-x-auto rounded-xl border">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>
                              {localized("Component", "Composant")}
                            </TableHead>
                            <TableHead>{localized("State", "État")}</TableHead>
                            <TableHead>
                              {localized("Requirement", "Exigence")}
                            </TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          <TableRow>
                            <TableCell>Input</TableCell>
                            <TableCell>
                              {localized("Invalid", "Invalide")}
                            </TableCell>
                            <TableCell>Message + aria-invalid</TableCell>
                          </TableRow>
                          <TableRow>
                            <TableCell>Dialog</TableCell>
                            <TableCell>{localized("Open", "Ouvert")}</TableCell>
                            <TableCell>Focus trap + Escape</TableCell>
                          </TableRow>
                        </TableBody>
                      </Table>
                    </div>
                  </TabsContent>
                  <TabsContent
                    className="mt-3 text-sm text-muted-foreground"
                    value="usage"
                  >
                    {localized(
                      "Prefer semantic components and translation keys.",
                      "Privilégiez les composants sémantiques et les clés de traduction.",
                    )}
                  </TabsContent>
                </Tabs>

                <Pagination aria-label={localized("Pages", "Pages")}>
                  <PaginationContent>
                    <PaginationItem>
                      <PaginationPrevious
                        ariaLabel={localized(
                          "Go to previous page",
                          "Aller à la page précédente",
                        )}
                        href="#gallery-navigation"
                        label={localized("Previous", "Précédent")}
                      />
                    </PaginationItem>
                    <PaginationItem>
                      <PaginationLink
                        aria-label="Page 1"
                        href="#gallery-navigation"
                        isActive
                      >
                        1
                      </PaginationLink>
                    </PaginationItem>
                    <PaginationItem>
                      <PaginationLink
                        aria-label="Page 2"
                        href="#gallery-navigation"
                      >
                        2
                      </PaginationLink>
                    </PaginationItem>
                    <PaginationItem>
                      <PaginationEllipsis
                        label={localized("More pages", "Autres pages")}
                      />
                    </PaginationItem>
                    <PaginationItem>
                      <PaginationNext
                        ariaLabel={localized(
                          "Go to next page",
                          "Aller à la page suivante",
                        )}
                        href="#gallery-navigation"
                        label={localized("Next", "Suivant")}
                      />
                    </PaginationItem>
                  </PaginationContent>
                </Pagination>
              </div>

              <ScrollArea
                aria-label={localized("Recent states", "États récents")}
                className="h-72 rounded-xl border"
              >
                <div className="p-4">
                  <h3 className="text-sm font-semibold">
                    {localized("Recent states", "États récents")}
                  </h3>
                  <div className="mt-3">
                    {[
                      [
                        localized("Saved", "Enregistré"),
                        localized("Now", "Maintenant"),
                      ],
                      [localized("Processing", "Traitement"), "2 min"],
                      [localized("Needs review", "À vérifier"), "8 min"],
                      [localized("Ready", "Prêt"), "12 min"],
                      [localized("Archived", "Archivé"), "1 h"],
                    ].map(([label, time], index) => (
                      <div key={label}>
                        {index > 0 ? <Separator /> : null}
                        <div className="flex min-h-14 items-center justify-between gap-4 py-2">
                          <span className="text-sm font-medium">{label}</span>
                          <span className="text-xs text-muted-foreground">
                            {time}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </ScrollArea>
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              <div className="space-y-3 rounded-xl border p-4">
                <StateLabel>
                  {localized("Entity combobox", "Liste d’entités")}
                </StateLabel>
                <Combobox
                  ariaLabel={localized("Vehicle", "Véhicule")}
                  defaultValue="vehicle-1"
                  emptyMessage={localized("No vehicle", "Aucun véhicule")}
                  options={[
                    {
                      label: "2025 Northstar Touring",
                      value: "vehicle-1",
                    },
                    {
                      label: "2024 Meridian Sport",
                      value: "vehicle-2",
                    },
                    {
                      label: "2023 Atlas Utility",
                      value: "vehicle-3",
                    },
                  ]}
                  placeholder={localized("Select", "Sélectionner")}
                  searchPlaceholder={localized("Search", "Rechercher")}
                />
              </div>

              <Command className="h-64 rounded-xl border">
                <CommandInput
                  aria-label={localized(
                    "Find a destination",
                    "Trouver une destination",
                  )}
                  placeholder={localized(
                    "Find a destination",
                    "Trouver une destination",
                  )}
                />
                <CommandList>
                  <CommandEmpty>
                    {localized("No result", "Aucun résultat")}
                  </CommandEmpty>
                  <CommandGroup
                    heading={localized("Destinations", "Destinations")}
                  >
                    <CommandItem value="inventory-inventaire">
                      <Boxes aria-hidden="true" />
                      {localized("Inventory", "Inventaire")}
                      <CommandShortcut>⌘1</CommandShortcut>
                    </CommandItem>
                    <CommandItem value="people-personnes">
                      <Users aria-hidden="true" />
                      {localized("People", "Personnes")}
                      <CommandShortcut>⌘2</CommandShortcut>
                    </CommandItem>
                    <CommandSeparator />
                    <CommandItem value="documents">
                      <FileText aria-hidden="true" />
                      Documents
                      <CommandShortcut>⌘3</CommandShortcut>
                    </CommandItem>
                  </CommandGroup>
                </CommandList>
              </Command>

              <SidebarProvider className="min-h-0 overflow-hidden rounded-xl border lg:col-span-2">
                <Sidebar
                  className="w-full border-r sm:w-48"
                  collapsible="none"
                  mobileCloseLabel={localized(
                    "Close navigation",
                    "Fermer la navigation",
                  )}
                  mobileDescription={localized(
                    "Displays workspace navigation.",
                    "Affiche la navigation de l’espace de travail.",
                  )}
                  mobileTitle={localized("Navigation", "Navigation")}
                >
                  <SidebarHeader>
                    <p className="px-2 py-2 text-sm font-semibold">Vynlo</p>
                  </SidebarHeader>
                  <SidebarContent>
                    <SidebarGroup>
                      <SidebarGroupLabel>
                        {localized("Workspace", "Espace")}
                      </SidebarGroupLabel>
                      <SidebarGroupContent>
                        <SidebarMenu>
                          <SidebarMenuItem>
                            <SidebarMenuButton asChild isActive>
                              <a href="#gallery-navigation">
                                <Boxes aria-hidden="true" />
                                <span>
                                  {localized("Inventory", "Inventaire")}
                                </span>
                              </a>
                            </SidebarMenuButton>
                          </SidebarMenuItem>
                          <SidebarMenuItem>
                            <SidebarMenuButton asChild>
                              <a href="#gallery-navigation">
                                <FileText aria-hidden="true" />
                                <span>Documents</span>
                              </a>
                            </SidebarMenuButton>
                          </SidebarMenuItem>
                          <SidebarMenuItem>
                            <SidebarMenuButton asChild>
                              <a href="#gallery-navigation">
                                <Settings2 aria-hidden="true" />
                                <span>{localized("Settings", "Réglages")}</span>
                              </a>
                            </SidebarMenuButton>
                          </SidebarMenuItem>
                        </SidebarMenu>
                      </SidebarGroupContent>
                    </SidebarGroup>
                  </SidebarContent>
                </Sidebar>
                <div className="hidden min-h-64 flex-1 items-center justify-center p-4 text-center text-sm text-muted-foreground sm:flex">
                  {localized("Adaptive content", "Contenu adaptatif")}
                </div>
              </SidebarProvider>
            </div>
          </div>
        </GallerySection>

        <GallerySection
          description={localized(
            "Focused decisions, temporary surfaces, menus, and help",
            "Décisions ciblées, surfaces temporaires, menus et aide",
          )}
          title={text.layers}
        >
          <div className="flex flex-wrap gap-3">
            <Dialog>
              <DialogTrigger asChild>
                <Button className="min-h-11" variant="outline">
                  {localized("Open dialog", "Ouvrir le dialogue")}
                </Button>
              </DialogTrigger>
              <DialogContent closeLabel={text.close}>
                <DialogHeader>
                  <DialogTitle>Confirmation</DialogTitle>
                  <DialogDescription>
                    {localized(
                      "Dialogs reserve attention for a focused decision.",
                      "Les dialogues réservent l’attention à une décision précise.",
                    )}
                  </DialogDescription>
                </DialogHeader>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button className="min-h-11" variant="outline">
                      {text.close}
                    </Button>
                  </DialogClose>
                </DialogFooter>
              </DialogContent>
            </Dialog>

            <Sheet>
              <SheetTrigger asChild>
                <Button className="min-h-11" variant="outline">
                  <Menu aria-hidden="true" />
                  {localized("Open sheet", "Ouvrir le panneau")}
                </Button>
              </SheetTrigger>
              <SheetContent closeLabel={text.close}>
                <SheetHeader>
                  <SheetTitle>{localized("More", "Plus")}</SheetTitle>
                  <SheetDescription>
                    {localized(
                      "A touch-friendly secondary surface.",
                      "Une surface secondaire adaptée au tactile.",
                    )}
                  </SheetDescription>
                </SheetHeader>
                <SheetFooter>
                  <SheetClose asChild>
                    <Button className="min-h-11">{text.close}</Button>
                  </SheetClose>
                </SheetFooter>
              </SheetContent>
            </Sheet>

            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button className="min-h-11" variant="destructive">
                  {localized("Destructive action", "Action destructive")}
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>
                    {localized("Remove this record?", "Supprimer cette fiche?")}
                  </AlertDialogTitle>
                  <AlertDialogDescription>
                    {localized(
                      "This example requires an explicit confirmation.",
                      "Cet exemple exige une confirmation explicite.",
                    )}
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>{text.close}</AlertDialogCancel>
                  <AlertDialogAction variant="destructive">
                    {localized("Confirm", "Confirmer")}
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>

            <Drawer>
              <DrawerTrigger asChild>
                <Button className="min-h-11" variant="outline">
                  {localized("Open drawer", "Ouvrir le tiroir")}
                </Button>
              </DrawerTrigger>
              <DrawerContent>
                <DrawerHeader>
                  <DrawerTitle>
                    {localized("Quick update", "Mise à jour rapide")}
                  </DrawerTitle>
                  <DrawerDescription>
                    {localized(
                      "Drawers support short, touch-first work.",
                      "Les tiroirs conviennent aux tâches tactiles et brèves.",
                    )}
                  </DrawerDescription>
                </DrawerHeader>
                <DrawerFooter>
                  <DrawerClose asChild>
                    <Button className="min-h-11">{text.close}</Button>
                  </DrawerClose>
                </DrawerFooter>
              </DrawerContent>
            </Drawer>

            <Popover>
              <PopoverTrigger asChild>
                <Button className="min-h-11" variant="outline">
                  {localized("Open popover", "Ouvrir l’encart")}
                </Button>
              </PopoverTrigger>
              <PopoverContent align="start">
                <PopoverHeader>
                  <PopoverTitle>
                    {localized("Context", "Contexte")}
                  </PopoverTitle>
                  <PopoverDescription>
                    {localized(
                      "Supporting detail stays near its trigger.",
                      "Le détail reste près de son déclencheur.",
                    )}
                  </PopoverDescription>
                </PopoverHeader>
              </PopoverContent>
            </Popover>

            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button className="min-h-11" variant="outline">
                  Menu <ChevronDown aria-hidden="true" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start">
                <DropdownMenuLabel>Actions</DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem className="min-h-11">
                  {localized("Primary", "Primaire")}
                </DropdownMenuItem>
                <DropdownMenuItem className="min-h-11" disabled>
                  {localized("Disabled", "Désactivé")}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>

            <Tooltip>
              <TooltipTrigger asChild>
                <Button className="min-h-11" variant="ghost">
                  {localized("Hover or focus", "Survoler ou cibler")}
                </Button>
              </TooltipTrigger>
              <TooltipContent>
                {localized("Helpful context", "Contexte utile")}
              </TooltipContent>
            </Tooltip>
          </div>
        </GallerySection>
      </div>
    </main>
  );
}
