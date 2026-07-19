/* Hallmark · composition: status-badge · system: Vynlo System */

import type { ComponentProps } from "react";

import { Badge, cn } from "@vynlo/ui-web";

type BadgeProps = ComponentProps<typeof Badge>;

export type StatusTone = "neutral" | "info" | "success" | "warning" | "error";

const toneVariant: Record<StatusTone, NonNullable<BadgeProps["variant"]>> = {
  neutral: "outline",
  info: "default",
  success: "success",
  warning: "warning",
  error: "destructive",
};

export type StatusBadgeProps = Omit<BadgeProps, "children" | "variant"> & {
  label: string;
  tone?: StatusTone;
  showIndicator?: boolean;
};

export function StatusBadge({
  label,
  tone = "neutral",
  showIndicator = true,
  className,
  ...props
}: StatusBadgeProps) {
  return (
    <Badge
      variant={toneVariant[tone]}
      className={cn("gap-1.5", className)}
      {...props}
    >
      {showIndicator ? (
        <span aria-hidden="true" className="size-1.5 rounded-full bg-current" />
      ) : null}
      {label}
    </Badge>
  );
}
