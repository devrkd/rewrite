import type { TriggerMode } from "./types.js";

/** Anchored to the end of string, case-insensitive. */
const TRIGGER_RE = /\/(fixit|rewrite|formal|casual)$/i;

export type DetectResult =
  | { matched: true; mode: TriggerMode; text: string }
  | { matched: false };

export function detectTrigger(input: string): DetectResult {
  const trimmed = input.trimEnd();
  const match = TRIGGER_RE.exec(trimmed);
  if (!match) return { matched: false };

  const mode = match[1].toLowerCase() as TriggerMode;
  const text = trimmed.slice(0, trimmed.lastIndexOf(match[0])).trimEnd();
  return { matched: true, mode, text };
}

export const TRIGGER_COMMANDS = ["/fixit", "/rewrite", "/formal", "/casual"];
