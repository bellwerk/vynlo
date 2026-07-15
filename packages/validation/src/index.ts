import { z } from "zod";

export const identifierSchema = z.string().min(1);
export const packageName = "@vynlo/validation" as const;
