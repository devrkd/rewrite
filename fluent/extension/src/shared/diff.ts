/**
 * Diff computation using the `diff` package — no eval, fully CSP-safe.
 */
import * as Diff from "diff";
import type { DiffSegment } from "./types.js";

export function computeDiff(original: string, corrected: string): DiffSegment[] {
  const changes = Diff.diffWordsWithSpace(original, corrected);
  return changes.map((part) => ({
    type: part.added ? "insert" : part.removed ? "delete" : "equal",
    value: part.value,
  }));
}
