/* Hallmark · composition: error-state · system: Vynlo System */

import { TriangleAlertIcon } from "lucide-react";

import { Alert, AlertDescription, AlertTitle, Button, cn } from "@vynlo/ui-web";

export type ErrorStateProps = {
  title: string;
  description?: string;
  retryLabel?: string;
  onRetry?: () => void;
  retrying?: boolean;
  retryingLabel?: string;
  className?: string;
};

export function ErrorState({
  title,
  description,
  retryLabel,
  onRetry,
  retrying = false,
  retryingLabel,
  className,
}: ErrorStateProps) {
  return (
    <Alert
      variant="destructive"
      aria-live="assertive"
      className={cn("rounded-[var(--radius-panel)] p-4", className)}
    >
      <TriangleAlertIcon aria-hidden="true" />
      <AlertTitle className="line-clamp-none">{title}</AlertTitle>
      <AlertDescription>
        {description ? <p>{description}</p> : null}
        {retryLabel && onRetry ? (
          <Button
            type="button"
            variant="outline"
            status={retrying ? "loading" : "idle"}
            {...(retrying && retryingLabel
              ? { statusLabel: retryingLabel }
              : {})}
            onClick={onRetry}
            className="mt-2"
          >
            {retrying && retryingLabel ? retryingLabel : retryLabel}
          </Button>
        ) : null}
      </AlertDescription>
    </Alert>
  );
}
