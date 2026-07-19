import * as React from "react";

import { cn } from "@vynlo/ui-web/lib/utils";
import type { ControlStatus } from "#lib/control-status";

type TextareaProps = React.ComponentProps<"textarea"> & {
  status?: ControlStatus;
};

function Textarea({
  className,
  status = "idle",
  "aria-invalid": ariaInvalid,
  ...props
}: TextareaProps) {
  return (
    <textarea
      data-slot="textarea"
      data-status={status}
      aria-busy={status === "loading" || undefined}
      aria-invalid={status === "error" ? true : ariaInvalid}
      className={cn(
        "flex field-sizing-content min-h-24 w-full resize-y rounded-[var(--radius-control)] border border-input bg-card px-3 pe-10 py-2 text-base shadow-xs outline-none transition-opacity duration-[var(--duration-fast)] ease-[var(--ease-out)] placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/30 data-[status=success]:border-success data-[status=loading]:cursor-progress md:text-sm dark:bg-input/30 dark:aria-invalid:ring-destructive/40",
        className,
      )}
      {...props}
    />
  );
}

export { Textarea, type TextareaProps };
