"use client";

import * as React from "react";
import { CheckIcon } from "lucide-react";
import { Checkbox as CheckboxPrimitive } from "radix-ui";

import { cn } from "@vynlo/ui-web/lib/utils";

function Checkbox({
  className,
  ...props
}: React.ComponentProps<typeof CheckboxPrimitive.Root>) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      className={cn(
        "peer relative grid size-11 min-h-11 min-w-11 shrink-0 place-content-center rounded-[var(--radius-control)] border border-transparent bg-transparent text-primary-foreground outline-none transition-opacity duration-[var(--duration-fast)] ease-[var(--ease-out)] before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:size-5 before:-translate-x-1/2 before:-translate-y-1/2 before:rounded-md before:border before:border-input before:bg-card before:shadow-xs before:content-[''] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:before:border-destructive aria-invalid:ring-destructive/30 data-[state=checked]:before:border-primary data-[state=checked]:before:bg-primary dark:before:bg-input/30 dark:aria-invalid:ring-destructive/40 dark:data-[state=checked]:before:bg-primary",
        className,
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator
        data-slot="checkbox-indicator"
        className="relative z-10 grid place-content-center text-current transition-none"
      >
        <CheckIcon className="size-4" />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  );
}

export { Checkbox };
