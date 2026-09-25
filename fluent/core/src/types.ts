import { z } from "zod";

export const TriggerModeSchema = z.enum(["fixit", "rewrite", "formal", "casual"]);
export type TriggerMode = z.infer<typeof TriggerModeSchema>;

export const ProviderSchema = z.enum(["anthropic", "openai", "gemini"]);
export type Provider = z.infer<typeof ProviderSchema>;

export const CorrectRequestSchema = z.object({
  text: z.string().min(1).max(8000),
  mode: TriggerModeSchema,
  provider: ProviderSchema.optional(),
});
export type CorrectRequest = z.infer<typeof CorrectRequestSchema>;

export interface DiffSegment {
  type: "equal" | "insert" | "delete";
  value: string;
}

export interface CorrectResponse {
  original: string;
  corrected: string;
  diff: DiffSegment[];
}

export interface HealthResponse {
  status: "ok";
  provider: Provider;
  version: string;
}

export interface ErrorResponse {
  error: string;
  code: string;
}
