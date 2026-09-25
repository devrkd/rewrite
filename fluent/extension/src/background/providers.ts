/**
 * Direct LLM API calls from the background service worker.
 * All fetches happen here (not in content scripts) to avoid CORS issues.
 */
import type { TriggerMode, Provider } from "../shared/types.js";
import { getSystemPrompt } from "../shared/prompts.js";
import { getToken, isConnected, getAllStatuses } from "./auth.js";

// ── Provider interface ─────────────────────────────────────────────────────

async function callAnthropic(text: string, mode: TriggerMode, accessToken: string): Promise<string> {
  const { settings } = await chrome.storage.local.get("settings");
  const model = settings?.anthropicModel ?? "claude-3-5-sonnet-latest";

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": accessToken,
      "anthropic-version": "2023-06-01",
      "anthropic-dangerous-direct-browser-access": "true",
    },
    body: JSON.stringify({
      model,
      max_tokens: 4096,
      system: getSystemPrompt(mode),
      messages: [{ role: "user", content: text }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Anthropic API error (${res.status}): ${body}`);
  }

  const data = (await res.json()) as { content: { type: string; text: string }[] };
  const block = data.content[0];
  if (block?.type !== "text") throw new Error("Unexpected response from Anthropic");
  return block.text.trim();
}

async function callOpenAI(text: string, mode: TriggerMode, accessToken: string): Promise<string> {
  const { settings } = await chrome.storage.local.get("settings");
  const model = settings?.openaiModel ?? "gpt-4o-mini";

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: getSystemPrompt(mode) },
        { role: "user", content: text },
      ],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenAI API error (${res.status}): ${body}`);
  }

  const data = (await res.json()) as { choices: { message: { content: string } }[] };
  const content = data.choices[0]?.message.content;
  if (!content) throw new Error("Empty response from OpenAI");
  return content.trim();
}

// ── Resolve active provider ────────────────────────────────────────────────

async function resolveProvider(requested?: Provider): Promise<Provider> {
  if (requested) {
    if (!(await isConnected(requested))) {
      throw new NotConnectedError(`"${requested}" is not connected. Open Fluent settings to sign in.`);
    }
    return requested;
  }

  const statuses = await getAllStatuses();
  const active = statuses.find((s) => s.connected);
  if (!active) {
    throw new NotConnectedError("No AI provider connected. Click the Fluent icon to sign in.");
  }
  return active.provider;
}

// ── Public API ─────────────────────────────────────────────────────────────

export async function correctText(
  text: string,
  mode: TriggerMode,
  provider?: Provider
): Promise<string> {
  const MAX_LENGTH = 8000;
  if (text.length > MAX_LENGTH) {
    throw new Error(`Input is too long (max ${MAX_LENGTH} characters).`);
  }

  const resolvedProvider = await resolveProvider(provider);
  const token = await getToken(resolvedProvider);
  if (!token) throw new NotConnectedError("Token missing — please reconnect.");

  switch (resolvedProvider) {
    case "anthropic": return callAnthropic(text, mode, token.accessToken);
    case "openai":    return callOpenAI(text, mode, token.accessToken);
  }
}

export class NotConnectedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NotConnectedError";
  }
}
