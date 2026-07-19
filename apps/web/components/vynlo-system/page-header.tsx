/* Hallmark · composition: page-header · system: Vynlo System */

import type { ReactNode } from "react";

import { cn } from "@vynlo/ui-web";

export type PageHeaderProps = {
  title: string;
  description?: string;
  eyebrow?: string;
  leading?: ReactNode;
  actions?: ReactNode;
  meta?: ReactNode;
  className?: string;
  titleId?: string;
};

export function PageHeader({
  title,
  description,
  eyebrow,
  leading,
  actions,
  meta,
  className,
  titleId,
}: PageHeaderProps) {
  return (
    <header
      className={cn(
        "flex flex-col gap-4 border-b border-border pb-5 sm:flex-row sm:items-end sm:justify-between",
        className,
      )}
    >
      <div className="flex min-w-0 items-start gap-3">
        {leading ? <div className="shrink-0">{leading}</div> : null}
        <div className="min-w-0 space-y-1.5">
          {eyebrow ? (
            <p className="text-xs font-semibold tracking-[0.08em] text-muted-foreground uppercase">
              {eyebrow}
            </p>
          ) : null}
          <h1
            id={titleId}
            className="text-balance text-2xl font-semibold tracking-[-0.02em] text-foreground sm:text-3xl"
          >
            {title}
          </h1>
          {description ? (
            <p className="max-w-3xl text-pretty text-sm leading-6 text-muted-foreground sm:text-base">
              {description}
            </p>
          ) : null}
          {meta ? (
            <div className="pt-1 text-sm text-muted-foreground">{meta}</div>
          ) : null}
        </div>
      </div>
      {actions ? (
        <div className="flex min-h-11 shrink-0 flex-wrap items-center gap-2 sm:justify-end">
          {actions}
        </div>
      ) : null}
    </header>
  );
}
