/* Hallmark · component: button · genre: modern-minimal · theme: Vynlo System
 * states: default · hover · focus · active · disabled · loading · error · success
 * contrast: AA · touch target: 44px · focus: instant
 */

import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { CheckIcon, LoaderCircleIcon, TriangleAlertIcon } from "lucide-react";
import { Slot } from "radix-ui";

import { cn } from "@vynlo/ui-web/lib/utils";
import type { ControlStatus } from "#lib/control-status";

const buttonVariants = cva(
  "inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center gap-2 rounded-[var(--radius-control)] border border-transparent text-sm font-medium whitespace-nowrap outline-none transition-[opacity,transform] duration-[var(--duration-fast)] ease-[var(--ease-out)] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 active:translate-y-px disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/30 data-[status=error]:border-destructive data-[status=error]:bg-destructive data-[status=error]:text-destructive-foreground data-[status=success]:border-success data-[status=success]:bg-success data-[status=success]:text-success-foreground dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive:
          "bg-destructive text-destructive-foreground hover:bg-destructive/90 focus-visible:ring-destructive/30 dark:focus-visible:ring-destructive/40",
        outline:
          "border bg-background shadow-xs hover:bg-accent hover:text-accent-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost:
          "hover:bg-accent hover:text-accent-foreground dark:hover:bg-accent/50",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-11 px-4 py-2 has-[>svg]:px-3",
        xs: "h-11 gap-1 px-3 text-xs has-[>svg]:px-2.5 [&_svg:not([class*='size-'])]:size-3",
        sm: "h-11 gap-1.5 px-3 has-[>svg]:px-2.5",
        lg: "h-12 px-6 has-[>svg]:px-4",
        icon: "size-11",
        "icon-xs": "size-11 [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-11",
        "icon-lg": "size-12",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

type ButtonProps = React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean;
    status?: ControlStatus;
    statusLabel?: string;
  };

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  status = "idle",
  statusLabel,
  children,
  disabled,
  "aria-invalid": ariaInvalid,
  "aria-disabled": ariaDisabled,
  ...props
}: ButtonProps) {
  const Comp = asChild ? Slot.Root : "button";
  const isLoading = status === "loading";
  const statusIcon =
    status === "loading" ? (
      <LoaderCircleIcon
        aria-hidden="true"
        className="animate-spin motion-reduce:animate-none"
      />
    ) : status === "error" ? (
      <TriangleAlertIcon aria-hidden="true" />
    ) : status === "success" ? (
      <CheckIcon aria-hidden="true" />
    ) : null;

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      data-status={status}
      aria-busy={isLoading || undefined}
      aria-invalid={status === "error" ? true : ariaInvalid}
      aria-disabled={asChild && (disabled || isLoading) ? true : ariaDisabled}
      disabled={asChild ? undefined : disabled || isLoading}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    >
      {asChild ? (
        children
      ) : (
        <>
          {statusIcon}
          {children}
          {statusLabel ? (
            <span className="sr-only" role="status">
              {statusLabel}
            </span>
          ) : null}
        </>
      )}
    </Comp>
  );
}

export { Button, buttonVariants, type ButtonProps };
