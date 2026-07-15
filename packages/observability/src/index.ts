export interface Logger {
  info(message: string, context?: unknown): void;
}

export function createLogger(service: string): Logger {
  return {
    info(message, context) {
      process.stdout.write(
        `${JSON.stringify({ context, level: "info", message, service })}\\n`,
      );
    },
  };
}

export const packageName = "@vynlo/observability" as const;
