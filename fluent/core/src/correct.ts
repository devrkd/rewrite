import type { CorrectRequest, CorrectResponse, Provider } from "./types.js";
import { createProvider } from "./providers/index.js";
import { computeDiff } from "./diff.js";
import { getAllStatus, isConnected } from "./auth/store.js";

const MAX_LENGTH = parseInt(process.env.MAX_INPUT_LENGTH ?? "8000", 10);

/** Simple in-memory cache keyed by "provider:mode:text" */
const cache = new Map<string, string>();

/** Returns the first connected provider, or throws if none are connected. */
function resolveProvider(requested?: Provider): Provider {
  if (requested) {
    if (!isConnected(requested)) {
      throw new Error(
        `Provider "${requested}" is not connected. Open Fluent Settings and sign in first.`
      );
    }
    return requested;
  }

  const status = getAllStatus();
  const active = (Object.entries(status) as [Provider, boolean][]).find(
    ([, connected]) => connected
  )?.[0];

  if (!active) {
    throw new Error(
      "No AI provider is connected. Open Fluent Settings and sign in with Claude or ChatGPT."
    );
  }

  return active;
}

export async function correctText(req: CorrectRequest): Promise<CorrectResponse> {
  if (req.text.length > MAX_LENGTH) {
    throw new Error(`Input exceeds maximum length of ${MAX_LENGTH} characters`);
  }

  const provider = resolveProvider(req.provider);
  const cacheKey = `${provider}:${req.mode}:${req.text}`;

  let corrected = cache.get(cacheKey);
  if (!corrected) {
    const llm = await createProvider(provider);
    corrected = await llm.correct(req.text, req.mode);
    cache.set(cacheKey, corrected);
  }

  return {
    original: req.text,
    corrected,
    diff: computeDiff(req.text, corrected),
  };
}
