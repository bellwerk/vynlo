/* Hallmark · composition: job-status · system: Vynlo System */

import {
  BanIcon,
  CheckCircle2Icon,
  CircleAlertIcon,
  Clock3Icon,
  LoaderCircleIcon,
} from "lucide-react";

import { Button, Progress, cn } from "@vynlo/ui-web";

import { StatusBadge, type StatusTone } from "./status-badge";

export type JobState =
  "queued" | "running" | "succeeded" | "failed" | "cancelled";

const jobPresentation = {
  queued: { icon: Clock3Icon, tone: "neutral" },
  running: { icon: LoaderCircleIcon, tone: "info" },
  succeeded: { icon: CheckCircle2Icon, tone: "success" },
  failed: { icon: CircleAlertIcon, tone: "error" },
  cancelled: { icon: BanIcon, tone: "neutral" },
} satisfies Record<JobState, { icon: typeof Clock3Icon; tone: StatusTone }>;

export type JobStatusProps = {
  state: JobState;
  title: string;
  statusLabel: string;
  description?: string;
  progress?: number;
  progressLabel?: string;
  retryLabel?: string;
  onRetry?: () => void;
  retrying?: boolean;
  retryingLabel?: string;
  className?: string;
};

export function JobStatus({
  state,
  title,
  statusLabel,
  description,
  progress,
  progressLabel,
  retryLabel,
  onRetry,
  retrying = false,
  retryingLabel,
  className,
}: JobStatusProps) {
  const { icon: Icon, tone } = jobPresentation[state];
  const hasProgress = typeof progress === "number";
  const isFailure = state === "failed";

  return (
    <section
      aria-label={title}
      role={isFailure ? "alert" : "status"}
      aria-live={isFailure ? "assertive" : "polite"}
      aria-busy={state === "running" || retrying || undefined}
      className={cn(
        "rounded-[var(--radius-panel)] border border-border bg-card p-4 shadow-[var(--shadow-panel)]",
        className,
      )}
    >
      <div className="flex items-start gap-3">
        <div className="flex size-11 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">
          <Icon
            aria-hidden="true"
            className={cn(
              "size-5",
              state === "running" && "animate-spin motion-reduce:animate-none",
            )}
          />
        </div>
        <div className="min-w-0 flex-1 space-y-3">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <h2 className="font-semibold text-foreground">{title}</h2>
              {description ? (
                <p className="mt-1 text-sm leading-5 text-muted-foreground">
                  {description}
                </p>
              ) : null}
            </div>
            <StatusBadge label={statusLabel} tone={tone} />
          </div>
          {hasProgress ? (
            <div className="space-y-1.5">
              {progressLabel ? (
                <div className="flex justify-between gap-3 text-xs text-muted-foreground">
                  <span>{progressLabel}</span>
                  <span aria-hidden="true">{progress}%</span>
                </div>
              ) : null}
              <Progress
                value={progress}
                aria-label={progressLabel ?? statusLabel}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={progress}
              />
            </div>
          ) : null}
          {isFailure && retryLabel && onRetry ? (
            <Button
              type="button"
              variant="outline"
              status={retrying ? "loading" : "idle"}
              {...(retrying && retryingLabel
                ? { statusLabel: retryingLabel }
                : {})}
              onClick={onRetry}
            >
              {retrying && retryingLabel ? retryingLabel : retryLabel}
            </Button>
          ) : null}
        </div>
      </div>
    </section>
  );
}
