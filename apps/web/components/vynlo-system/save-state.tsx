/* Hallmark · composition: save-state · system: Vynlo System */

import {
  CheckCircle2Icon,
  CircleAlertIcon,
  CircleDotIcon,
  LoaderCircleIcon,
  PencilLineIcon,
} from "lucide-react";

import { cn } from "@vynlo/ui-web";

export type SaveStateKind = "idle" | "dirty" | "saving" | "saved" | "error";

const stateIcon = {
  idle: CircleDotIcon,
  dirty: PencilLineIcon,
  saving: LoaderCircleIcon,
  saved: CheckCircle2Icon,
  error: CircleAlertIcon,
} satisfies Record<SaveStateKind, typeof CircleDotIcon>;

export type SaveStateProps = {
  state: SaveStateKind;
  label: string;
  detail?: string;
  className?: string;
};

export function SaveState({ state, label, detail, className }: SaveStateProps) {
  const Icon = stateIcon[state];
  const isError = state === "error";

  return (
    <div
      role={isError ? "alert" : "status"}
      aria-live={isError ? "assertive" : "polite"}
      aria-busy={state === "saving" || undefined}
      data-state={state}
      className={cn(
        "inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-control)] border border-border bg-card px-3 text-sm text-muted-foreground",
        "data-[state=saved]:border-success/40 data-[state=saved]:text-success",
        "data-[state=error]:border-destructive/40 data-[state=error]:text-destructive",
        className,
      )}
    >
      <Icon
        aria-hidden="true"
        className={cn(
          "size-4 shrink-0",
          state === "saving" && "animate-spin motion-reduce:animate-none",
        )}
      />
      <span className="font-medium">{label}</span>
      {detail ? (
        <span className="hidden text-muted-foreground sm:inline">{detail}</span>
      ) : null}
    </div>
  );
}
