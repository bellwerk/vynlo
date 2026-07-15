import {
  cloneElement,
  isValidElement,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type ReactElement,
} from "react";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  readonly asChild?: boolean;
}

const buttonClassName =
  "inline-flex min-h-11 items-center justify-center gap-2 border border-[#17251f] bg-[#17251f] px-5 py-3 text-sm font-bold text-[#f4f1e8] no-underline transition-transform focus-visible:outline-none motion-safe:hover:-translate-y-0.5";

export function Button({
  asChild = false,
  children,
  className = "",
  ...props
}: ButtonProps) {
  const classes = `${buttonClassName} ${className}`.trim();
  if (asChild && isValidElement(children)) {
    const child = children as ReactElement<{
      className?: string;
      style?: CSSProperties;
    }>;
    return cloneElement(child, {
      className: `${classes} ${child.props.className ?? ""}`.trim(),
      style: { color: "#f4f1e8", ...child.props.style },
    });
  }
  return (
    <button className={classes} type="button" {...props}>
      {children}
    </button>
  );
}

export const packageName = "@vynlo/ui-web" as const;
