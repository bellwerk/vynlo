"use client";

/* Hallmark · composition: confirm-destructive-action · system: Vynlo System */

import { useState, type ComponentProps } from "react";
import { TriangleAlertIcon } from "lucide-react";

import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogMedia,
  AlertDialogTitle,
  AlertDialogTrigger,
  Button,
} from "@vynlo/ui-web";

export type ConfirmDestructiveActionProps = {
  triggerLabel: string;
  title: string;
  description: string;
  confirmLabel: string;
  cancelLabel: string;
  pendingLabel: string;
  failureLabel: string;
  onConfirm: () => void | Promise<void>;
  disabled?: boolean;
  triggerVariant?: ComponentProps<typeof Button>["variant"];
  className?: string;
};

export function ConfirmDestructiveAction({
  triggerLabel,
  title,
  description,
  confirmLabel,
  cancelLabel,
  pendingLabel,
  failureLabel,
  onConfirm,
  disabled,
  triggerVariant = "destructive",
  className,
}: ConfirmDestructiveActionProps) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState(false);

  const handleOpenChange = (nextOpen: boolean) => {
    if (pending) return;
    setOpen(nextOpen);
    if (!nextOpen) setFailed(false);
  };

  const handleConfirm = async () => {
    setPending(true);
    setFailed(false);
    try {
      await onConfirm();
      setOpen(false);
    } catch {
      setFailed(true);
    } finally {
      setPending(false);
    }
  };

  return (
    <AlertDialog open={open} onOpenChange={handleOpenChange}>
      <AlertDialogTrigger asChild>
        <Button
          type="button"
          variant={triggerVariant}
          disabled={disabled}
          className={className}
        >
          {triggerLabel}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogMedia>
            <TriangleAlertIcon aria-hidden="true" />
          </AlertDialogMedia>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        {failed ? (
          <p
            role="alert"
            aria-live="assertive"
            className="text-sm text-destructive"
          >
            {failureLabel}
          </p>
        ) : null}
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>
            {cancelLabel}
          </AlertDialogCancel>
          <Button
            type="button"
            variant="destructive"
            status={pending ? "loading" : failed ? "error" : "idle"}
            {...(pending
              ? { statusLabel: pendingLabel }
              : failed
                ? { statusLabel: failureLabel }
                : {})}
            onClick={handleConfirm}
          >
            {pending ? pendingLabel : confirmLabel}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
