"use client";

/* Hallmark · composition: entity-combobox · system: Vynlo System */

import { useId, useState } from "react";
import { CheckIcon, ChevronsUpDownIcon, XIcon } from "lucide-react";

import {
  Button,
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
  Popover,
  PopoverContent,
  PopoverTrigger,
  cn,
} from "@vynlo/ui-web";

export type EntityComboboxProps<TEntity> = {
  label: string;
  options: readonly TEntity[];
  value: string | null;
  onValueChange: (value: string | null, entity: TEntity | null) => void;
  getOptionValue: (entity: TEntity) => string;
  getOptionLabel: (entity: TEntity) => string;
  getOptionKeywords?: (entity: TEntity) => readonly string[];
  isOptionDisabled?: (entity: TEntity) => boolean;
  placeholder: string;
  searchPlaceholder: string;
  emptyLabel: string;
  clearLabel?: string;
  description?: string;
  error?: string;
  disabled?: boolean;
  required?: boolean;
  id?: string;
  className?: string;
};

export function EntityCombobox<TEntity>({
  label,
  options,
  value,
  onValueChange,
  getOptionValue,
  getOptionLabel,
  getOptionKeywords,
  isOptionDisabled,
  placeholder,
  searchPlaceholder,
  emptyLabel,
  clearLabel,
  description,
  error,
  disabled,
  required,
  id: providedId,
  className,
}: EntityComboboxProps<TEntity>) {
  const generatedId = useId();
  const inputId = providedId ?? `${generatedId}-combobox`;
  const listId = `${inputId}-listbox`;
  const descriptionId = description ? `${inputId}-description` : undefined;
  const errorId = error ? `${inputId}-error` : undefined;
  const describedBy =
    [descriptionId, errorId].filter(Boolean).join(" ") || undefined;
  const [open, setOpen] = useState(false);

  const selectedEntity =
    options.find((option) => getOptionValue(option) === value) ?? null;
  const selectedLabel = selectedEntity
    ? getOptionLabel(selectedEntity)
    : placeholder;

  return (
    <Field
      className={cn("gap-2", className)}
      data-disabled={disabled || undefined}
      data-invalid={Boolean(error) || undefined}
    >
      <FieldLabel id={`${inputId}-label`} htmlFor={inputId}>
        {label}
        {required ? <span aria-hidden="true">*</span> : null}
      </FieldLabel>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            id={inputId}
            type="button"
            variant="outline"
            role="combobox"
            aria-expanded={open}
            aria-controls={listId}
            aria-labelledby={`${inputId}-label`}
            aria-describedby={describedBy}
            aria-invalid={Boolean(error) || undefined}
            aria-required={required || undefined}
            disabled={disabled}
            className="w-full justify-between bg-card px-3 font-normal"
          >
            <span
              className={cn(
                "truncate",
                !selectedEntity && "text-muted-foreground",
              )}
            >
              {selectedLabel}
            </span>
            <ChevronsUpDownIcon aria-hidden="true" className="opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent
          align="start"
          className="w-[var(--radix-popover-trigger-width)] p-0"
        >
          <Command>
            <CommandInput placeholder={searchPlaceholder} />
            <CommandList id={listId}>
              <CommandEmpty>{emptyLabel}</CommandEmpty>
              <CommandGroup>
                {clearLabel && value !== null ? (
                  <CommandItem
                    value={`__clear__ ${clearLabel}`}
                    onSelect={() => {
                      onValueChange(null, null);
                      setOpen(false);
                    }}
                  >
                    <XIcon aria-hidden="true" />
                    {clearLabel}
                  </CommandItem>
                ) : null}
                {options.map((option) => {
                  const optionValue = getOptionValue(option);
                  const optionLabel = getOptionLabel(option);
                  const keywords = getOptionKeywords?.(option).join(" ") ?? "";
                  const selected = optionValue === value;
                  const optionDisabled = isOptionDisabled?.(option);

                  return (
                    <CommandItem
                      key={optionValue}
                      value={`${optionValue} ${optionLabel} ${keywords}`}
                      {...(optionDisabled === undefined
                        ? {}
                        : { disabled: optionDisabled })}
                      aria-selected={selected}
                      onSelect={() => {
                        onValueChange(optionValue, option);
                        setOpen(false);
                      }}
                    >
                      <CheckIcon
                        aria-hidden="true"
                        className={cn(selected ? "opacity-100" : "opacity-0")}
                      />
                      <span className="truncate">{optionLabel}</span>
                    </CommandItem>
                  );
                })}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {description ? (
        <FieldDescription id={descriptionId}>{description}</FieldDescription>
      ) : null}
      {error ? <FieldError id={errorId}>{error}</FieldError> : null}
    </Field>
  );
}
