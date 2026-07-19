/* Hallmark · composition: empty-state · system: Vynlo System */

import type { ReactNode } from "react";
import { InboxIcon } from "lucide-react";

import { cn } from "@vynlo/ui-web";

export type EmptyStateProps = {
  title: string;
  description?: string;
  icon?: ReactNode;
  primaryAction?: ReactNode;
  secondaryAction?: ReactNode;
  className?: string;
  compact?: boolean;
};

export function EmptyState({
  title,
  description,
  icon,
  primaryAction,
  secondaryAction,
  className,
  compact = false,
}: EmptyStateProps) {
  return (
    <section
      aria-label={title}
      className={cn(
        "flex flex-col items-center justify-center rounded-[var(--radius-panel)] border border-dashed border-border bg-card text-center",
        compact ? "gap-3 p-5" : "min-h-64 gap-4 p-8",
        className,
      )}
    >
      <div
        aria-hidden="true"
        className="flex size-11 items-center justify-center rounded-full bg-muted text-muted-foreground [&_svg]:size-5"
      >
        {icon ?? <InboxIcon />}
      </div>
      <div className="max-w-md space-y-1.5">
        <h2 className="text-base font-semibold text-foreground">{title}</h2>
        {description ? (
          <p className="text-pretty text-sm leading-6 text-muted-foreground">
            {description}
          </p>
        ) : null}
      </div>
      {primaryAction || secondaryAction ? (
        <div className="flex min-h-11 flex-wrap items-center justify-center gap-2">
          {primaryAction}
          {secondaryAction}
        </div>
      ) : null}
    </section>
  );
}
