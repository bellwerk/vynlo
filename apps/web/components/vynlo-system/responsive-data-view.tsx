/* Hallmark · composition: responsive-data-view · system: Vynlo System */

import type { ReactNode } from "react";

import { cn } from "@vynlo/ui-web";

export type ResponsiveDataViewProps = {
  mobile: ReactNode;
  desktop: ReactNode;
  mobileLabel: string;
  desktopLabel: string;
  className?: string;
  mobileClassName?: string;
  desktopClassName?: string;
};

export function ResponsiveDataView({
  mobile,
  desktop,
  mobileLabel,
  desktopLabel,
  className,
  mobileClassName,
  desktopClassName,
}: ResponsiveDataViewProps) {
  return (
    <div className={className} data-vynlo-ui="responsive-data-view">
      <section
        aria-label={mobileLabel}
        className={cn("grid gap-3 md:hidden", mobileClassName)}
        data-vynlo-viewport="mobile"
      >
        {mobile}
      </section>
      <section
        aria-label={desktopLabel}
        className={cn("hidden min-w-0 md:block", desktopClassName)}
        data-vynlo-viewport="desktop"
      >
        {desktop}
      </section>
    </div>
  );
}
