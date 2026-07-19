"use client";

import * as React from "react";
import { CircleIcon } from "lucide-react";
import { RadioGroup as RadioGroupPrimitive } from "radix-ui";

import { cn } from "@vynlo/ui-web/lib/utils";

const keyboardSelectionTargets = new WeakSet<HTMLElement>();

function RadioGroup({
  className,
  dir,
  loop,
  onKeyDownCapture,
  orientation,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Root>) {
  const handleKeyDownCapture = React.useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      onKeyDownCapture?.(event);
      if (
        event.defaultPrevented ||
        event.metaKey ||
        event.ctrlKey ||
        event.altKey ||
        event.shiftKey
      ) {
        return;
      }

      const isHorizontalArrow =
        event.key === "ArrowLeft" || event.key === "ArrowRight";
      const isVerticalArrow =
        event.key === "ArrowUp" || event.key === "ArrowDown";
      if (
        (!isHorizontalArrow && !isVerticalArrow) ||
        (orientation === "horizontal" && !isHorizontalArrow) ||
        (orientation === "vertical" && !isVerticalArrow)
      ) {
        return;
      }

      const currentItem = (event.target as HTMLElement).closest<HTMLElement>(
        '[data-slot="radio-group-item"]',
      );
      if (!currentItem || !event.currentTarget.contains(currentItem)) {
        return;
      }

      const items = Array.from(
        event.currentTarget.querySelectorAll<HTMLElement>(
          '[data-slot="radio-group-item"]',
        ),
      ).filter(
        (item) =>
          !item.matches(':disabled, [data-disabled], [aria-disabled="true"]'),
      );
      const currentIndex = items.indexOf(currentItem);
      if (currentIndex === -1 || items.length < 2) {
        return;
      }

      const resolvedDirection = dir ?? event.currentTarget.dir ?? "ltr";
      let step =
        event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : -1;
      if (isHorizontalArrow && resolvedDirection === "rtl") {
        step *= -1;
      }

      const candidateIndex = currentIndex + step;
      const nextIndex =
        (loop ?? true)
          ? (candidateIndex + items.length) % items.length
          : candidateIndex;

      event.preventDefault();
      const nextItem = items[nextIndex];
      if (!nextItem) {
        return;
      }

      // Radix normally selects after an asynchronously moved focus event. Keep
      // the same roving-focus behavior, but make the selection deterministic
      // when the browser is under load.
      keyboardSelectionTargets.add(nextItem);
      try {
        nextItem.focus();
      } finally {
        keyboardSelectionTargets.delete(nextItem);
      }
      nextItem.click();
    },
    [dir, loop, onKeyDownCapture, orientation],
  );

  return (
    <RadioGroupPrimitive.Root
      data-slot="radio-group"
      className={cn("grid gap-3", className)}
      dir={dir}
      loop={loop}
      onKeyDownCapture={handleKeyDownCapture}
      orientation={orientation}
      {...props}
    />
  );
}

function RadioGroupItem({
  className,
  onFocus,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Item>) {
  const handleFocus = React.useCallback(
    (event: React.FocusEvent<HTMLButtonElement>) => {
      onFocus?.(event);
      if (keyboardSelectionTargets.has(event.currentTarget)) {
        // The group performs one explicit selection after focus. Prevent
        // Radix's document-level arrow-key detector from issuing a second one
        // when a key is held and repeat events are delivered.
        event.preventDefault();
      }
    },
    [onFocus],
  );

  return (
    <RadioGroupPrimitive.Item
      data-slot="radio-group-item"
      className={cn(
        "relative grid size-11 min-h-11 min-w-11 shrink-0 place-content-center rounded-[var(--radius-control)] border border-transparent bg-transparent text-primary outline-none transition-opacity duration-[var(--duration-fast)] ease-[var(--ease-out)] before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:size-5 before:-translate-x-1/2 before:-translate-y-1/2 before:rounded-full before:border before:border-input before:bg-card before:shadow-xs before:content-[''] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:before:border-destructive aria-invalid:ring-destructive/30 data-[state=checked]:before:border-primary dark:before:bg-input/30 dark:aria-invalid:ring-destructive/40",
        className,
      )}
      onFocus={handleFocus}
      {...props}
    >
      <RadioGroupPrimitive.Indicator
        data-slot="radio-group-indicator"
        className="relative z-10 flex items-center justify-center"
      >
        <CircleIcon className="size-2.5 fill-primary" />
      </RadioGroupPrimitive.Indicator>
    </RadioGroupPrimitive.Item>
  );
}

export { RadioGroup, RadioGroupItem };
