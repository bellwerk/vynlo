import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import type { ComponentProps } from "react";

import { cn } from "#lib/utils";

const buttonVariants = cva(
  "inline-flex min-h-11 shrink-0 items-center justify-center gap-2 whitespace-nowrap border text-sm font-bold no-underline transition-transform outline-none focus-visible:ring-3 focus-visible:ring-[var(--rust)] focus-visible:ring-offset-4 disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-[var(--rust)] motion-safe:hover:-translate-y-0.5 [&_svg]:pointer-events-none [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "border-[var(--ink)] bg-[var(--ink)] text-[var(--paper)] hover:bg-[color-mix(in_srgb,var(--ink)_90%,white)]",
        destructive:
          "border-[var(--rust)] bg-[var(--rust)] text-white hover:opacity-90",
        outline:
          "border-[var(--ink)] bg-transparent text-[var(--ink)] hover:bg-[var(--signal)]",
        secondary:
          "border-[var(--ink)] bg-[var(--signal)] text-[var(--ink)] hover:brightness-95",
        ghost:
          "border-transparent bg-transparent text-[var(--ink)] hover:bg-[color-mix(in_srgb,var(--ink)_8%,transparent)]",
        link: "min-h-0 border-transparent bg-transparent p-0 text-[var(--ink)] underline-offset-4 hover:underline",
      },
      size: {
        default: "px-5 py-3",
        sm: "min-h-9 px-3 py-2 text-xs",
        lg: "min-h-12 px-7 py-3.5",
        icon: "size-11 p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
);

export interface ButtonProps
  extends ComponentProps<"button">, VariantProps<typeof buttonVariants> {
  readonly asChild?: boolean;
}

function Button({
  asChild = false,
  className,
  size = "default",
  variant = "default",
  ...props
}: ButtonProps) {
  const Component = asChild ? Slot : "button";

  return (
    <Component
      className={cn(buttonVariants({ className, size, variant }))}
      data-size={size}
      data-slot="button"
      data-variant={variant}
      {...props}
    />
  );
}

export { Button, buttonVariants };
