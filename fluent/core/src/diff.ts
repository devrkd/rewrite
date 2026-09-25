import { diff_match_patch } from "diff-match-patch";
import type { DiffSegment } from "./types.js";

const dmp = new diff_match_patch();

export function computeDiff(original: string, corrected: string): DiffSegment[] {
  const diffs = dmp.diff_main(original, corrected);
  dmp.diff_cleanupSemantic(diffs);

  return diffs.map(([op, text]) => {
    const type: DiffSegment["type"] =
      op === 0 ? "equal" : op === 1 ? "insert" : "delete";
    return { type, value: text };
  });
}
