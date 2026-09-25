import type { TriggerMode } from "./types.js";

export interface TriggerConfig {
  command: string;
  mode: TriggerMode;
  description: string;
}

export const TRIGGERS: TriggerConfig[] = [
  {
    command: "/fixit",
    mode: "fixit",
    description: "Fix spelling and grammar only",
  },
  {
    command: "/rewrite",
    mode: "rewrite",
    description: "Rewrite for clarity and flow",
  },
  {
    command: "/formal",
    mode: "formal",
    description: "Rewrite in a formal tone",
  },
  {
    command: "/casual",
    mode: "casual",
    description: "Rewrite in a casual tone",
  },
];

/** Matches a trigger command anchored to the end of the string (case-insensitive). */
const TRIGGER_REGEX = /\/(fixit|rewrite|formal|casual)$/i;

export type DetectResult =
  | { matched: true; mode: TriggerMode; text: string }
  | { matched: false };

export function detectTrigger(input: string): DetectResult {
  const match = TRIGGER_REGEX.exec(input.trimEnd());
  if (!match) return { matched: false };

  const mode = match[1].toLowerCase() as TriggerMode;
  const text = input.slice(0, input.trimEnd().lastIndexOf(match[0])).trimEnd();
  return { matched: true, mode, text };
}
