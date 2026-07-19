"use client";

/* Hallmark · composition: money-input · system: Vynlo System */

import { useId, type ChangeEvent } from "react";

import {
  Field,
  FieldDescription,
  FieldError,
  FieldLabel,
  Input,
  cn,
  type InputProps,
} from "@vynlo/ui-web";

export type MoneyInputProps = Omit<
  InputProps,
  "type" | "value" | "defaultValue" | "onChange" | "inputMode"
> & {
  label: string;
  displayValue: string;
  currencyCode: string;
  onDisplayValueChange: (rawDisplayValue: string) => void;
  description?: string;
  error?: string;
  className?: string;
};

export function MoneyInput({
  label,
  displayValue,
  currencyCode,
  onDisplayValueChange,
  description,
  error,
  className,
  id: providedId,
  name,
  disabled,
  required,
  "aria-describedby": ariaDescribedBy,
  ...inputProps
}: MoneyInputProps) {
  const generatedId = useId();
  const inputId = providedId ?? `${generatedId}-input`;
  const descriptionId = description ? `${inputId}-description` : undefined;
  const errorId = error ? `${inputId}-error` : undefined;
  const describedBy =
    [ariaDescribedBy, descriptionId, errorId].filter(Boolean).join(" ") ||
    undefined;

  const handleChange = (event: ChangeEvent<HTMLInputElement>) => {
    // Deliberately forward the exact display string. Decimal parsing and minor-unit
    // conversion belong to the application service that owns the money rule.
    onDisplayValueChange(event.currentTarget.value);
  };

  return (
    <Field
      className={cn("gap-2", className)}
      data-disabled={disabled || undefined}
      data-invalid={Boolean(error) || undefined}
    >
      <div className="flex items-baseline justify-between gap-3">
        <FieldLabel htmlFor={inputId}>
          {label}
          {required ? <span aria-hidden="true">*</span> : null}
        </FieldLabel>
        <span className="text-xs font-medium text-muted-foreground">
          {currencyCode}
        </span>
      </div>
      <Input
        {...inputProps}
        id={inputId}
        name={name}
        type="text"
        inputMode="decimal"
        autoComplete="off"
        value={displayValue}
        disabled={disabled}
        required={required}
        aria-describedby={describedBy}
        aria-invalid={Boolean(error) || undefined}
        onChange={handleChange}
      />
      {description ? (
        <FieldDescription id={descriptionId}>{description}</FieldDescription>
      ) : null}
      {error ? <FieldError id={errorId}>{error}</FieldError> : null}
    </Field>
  );
}
