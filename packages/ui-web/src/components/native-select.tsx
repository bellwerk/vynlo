import * as React from "react";
import { ChevronDownIcon } from "lucide-react";

import { cn } from "@vynlo/ui-web/lib/utils";
import type { ControlStatus } from "#lib/control-status";

type NativeSelectProps = Omit<React.ComponentProps<"select">, "size"> & {
  size?: "sm" | "default";
  status?: ControlStatus;
};

function NativeSelect({
  className,
  size = "default",
  status = "idle",
  "aria-invalid": ariaInvalid,
  ...props
}: NativeSelectProps) {
  return (
    <div
      className="group/native-select relative w-full has-[select:disabled]:opacity-50"
      data-slot="native-select-wrapper"
    >
      <select
        data-slot="native-select"
        data-size={size}
        data-status={status}
        aria-busy={status === "loading" || undefined}
        aria-invalid={status === "error" ? true : ariaInvalid}
        className={cn(
          "h-11 w-full min-w-0 appearance-none rounded-[var(--radius-control)] border border-input bg-card px-3 py-2 pr-10 text-sm shadow-xs outline-none transition-opacity duration-[var(--duration-fast)] ease-[var(--ease-out)] selection:bg-primary selection:text-primary-foreground placeholder:text-muted-foreground disabled:cursor-not-allowed data-[size=sm]:h-11 dark:bg-input/30",
          "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
          "aria-invalid:border-destructive aria-invalid:ring-destructive/30 data-[status=success]:border-success data-[status=loading]:cursor-progress dark:aria-invalid:ring-destructive/40",
          className,
        )}
        {...props}
      />
      <ChevronDownIcon
        className="pointer-events-none absolute top-1/2 right-3.5 size-4 -translate-y-1/2 text-muted-foreground opacity-50 select-none"
        aria-hidden="true"
        data-slot="native-select-icon"
      />
    </div>
  );
}

function NativeSelectOption({
  className,
  ...props
}: React.ComponentProps<"option">) {
  return (
    <option
      data-slot="native-select-option"
      className={cn("bg-[Canvas] text-[CanvasText]", className)}
      {...props}
    />
  );
}

function NativeSelectOptGroup({
  className,
  ...props
}: React.ComponentProps<"optgroup">) {
  return (
    <optgroup
      data-slot="native-select-optgroup"
      className={cn("bg-[Canvas] text-[CanvasText]", className)}
      {...props}
    />
  );
}

export {
  NativeSelect,
  NativeSelectOptGroup,
  NativeSelectOption,
  type NativeSelectProps,
};
