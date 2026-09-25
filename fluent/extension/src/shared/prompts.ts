import type { TriggerMode } from "./types.js";

const PROMPTS: Record<TriggerMode, string> = {
  fixit:   "Fix ONLY spelling and grammar errors. Do NOT change meaning, tone, or wording beyond what is necessary. Return ONLY the corrected text — no explanations, no preamble.",
  rewrite: "Rewrite for clarity, conciseness, and natural flow while strictly preserving the original meaning. Return ONLY the rewritten text — no explanations, no preamble.",
  formal:  "Rewrite in a formal, professional tone. Avoid contractions. Preserve the original meaning. Return ONLY the rewritten text — no explanations, no preamble.",
  casual:  "Rewrite in a warm, conversational tone as if writing to a friend. Contractions are welcome. Preserve the original meaning. Return ONLY the rewritten text — no explanations, no preamble.",
};

export function getSystemPrompt(mode: TriggerMode): string {
  return PROMPTS[mode];
}
