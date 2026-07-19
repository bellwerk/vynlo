/* Hallmark · component: combobox · genre: modern-minimal · theme: Vynlo System
 * states: default · hover · focus · active · disabled · loading · error · success
 */
"use client";

import * as React from "react";
import { Check, ChevronsUpDown } from "lucide-react";

import { Button } from "@vynlo/ui-web/components/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@vynlo/ui-web/components/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@vynlo/ui-web/components/popover";
import { cn } from "@vynlo/ui-web/lib/utils";
import type { ControlStatus } from "#lib/control-status";

export interface ComboboxOption {
  readonly disabled?: boolean;
  readonly keywords?: readonly string[];
  readonly label: string;
  readonly value: string;
}

export interface ComboboxProps {
  readonly ariaLabel: string;
  readonly className?: string;
  readonly defaultValue?: string;
  readonly disabled?: boolean;
  readonly emptyMessage: string;
  readonly onValueChange?: (value: string) => void;
  readonly options: readonly ComboboxOption[];
  readonly placeholder: string;
  readonly searchPlaceholder: string;
  readonly status?: ControlStatus;
  readonly value?: string;
}

function Combobox({
  ariaLabel,
  className,
  defaultValue = "",
  disabled = false,
  emptyMessage,
  onValueChange,
  options,
  placeholder,
  searchPlaceholder,
  status = "idle",
  value,
}: ComboboxProps) {
  const [open, setOpen] = React.useState(false);
  const [uncontrolledValue, setUncontrolledValue] =
    React.useState(defaultValue);
  const selectedValue = value ?? uncontrolledValue;
  const selectedOption = options.find(
    (option) => option.value === selectedValue,
  );
  const isLoading = status === "loading";

  function select(nextValue: string) {
    if (value === undefined) setUncontrolledValue(nextValue);
    onValueChange?.(nextValue);
    setOpen(false);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          aria-expanded={open}
          aria-label={ariaLabel}
          className={cn(
            "w-full justify-between rounded-[var(--radius-control)] px-3 font-normal",
            !selectedOption && "text-muted-foreground",
            className,
          )}
          disabled={disabled}
          role="combobox"
          status={status}
          type="button"
          variant="outline"
        >
          <span className="truncate">
            {selectedOption?.label ?? placeholder}
          </span>
          <ChevronsUpDown aria-hidden="true" className="opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent
        align="start"
        className="w-[var(--radix-popover-trigger-width)] min-w-64 rounded-[var(--radius-panel)] p-0"
      >
        <Command>
          <CommandInput
            aria-label={searchPlaceholder}
            disabled={isLoading}
            placeholder={searchPlaceholder}
          />
          <CommandList>
            <CommandEmpty>{emptyMessage}</CommandEmpty>
            <CommandGroup>
              {options.map((option) => (
                <CommandItem
                  key={option.value}
                  onSelect={() => select(option.value)}
                  value={[
                    option.label,
                    option.value,
                    ...(option.keywords ?? []),
                  ].join(" ")}
                  {...(option.disabled === undefined
                    ? {}
                    : { disabled: option.disabled })}
                >
                  <Check
                    aria-hidden="true"
                    className={cn(
                      "opacity-0",
                      option.value === selectedValue && "opacity-100",
                    )}
                  />
                  <span>{option.label}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}

export { Combobox };
