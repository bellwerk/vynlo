import * as React from "react";

import { cn } from "@vynlo/ui-web/lib/utils";
import type { ControlStatus } from "#lib/control-status";

type InputProps = React.ComponentProps<"input"> & {
  status?: ControlStatus;
};

function Input({
  className,
  type,
  status = "idle",
  "aria-invalid": ariaInvalid,
  ...props
}: InputProps) {
  return (
    <input
      type={type}
      data-slot="input"
      data-status={status}
      aria-busy={status === "loading" || undefined}
      aria-invalid={status === "error" ? true : ariaInvalid}
      className={cn(
        "h-11 w-full min-w-0 rounded-[var(--radius-control)] border border-input bg-card px-3 pe-10 py-2 text-base shadow-xs outline-none transition-opacity duration-[var(--duration-fast)] ease-[var(--ease-out)] selection:bg-primary selection:text-primary-foreground file:inline-flex file:min-h-7 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50 md:text-sm dark:bg-input/30",
        "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
        "aria-invalid:border-destructive aria-invalid:ring-destructive/30 data-[status=success]:border-success data-[status=loading]:cursor-progress dark:aria-invalid:ring-destructive/40",
        className,
      )}
      {...props}
    />
  );
}

export { Input, type InputProps };
