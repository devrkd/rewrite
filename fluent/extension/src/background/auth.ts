/**
 * API key storage — keys are saved in chrome.storage.local
 * (Chrome encrypts this storage with the OS user account).
 * No OAuth, no client registration required.
 */
import type { Provider, StoredToken, ProviderStatus, ModelInfo } from "../shared/types.js";

const keyFor = (p: Provider) => `apikey_${p}`;

export async function getToken(provider: Provider): Promise<StoredToken | null> {
  const result = await chrome.storage.local.get(keyFor(provider));
  return (result[keyFor(provider)] as StoredToken) ?? null;
}

export async function saveApiKey(provider: Provider, apiKey: string): Promise<void> {
  const token: StoredToken = {
    accessToken: apiKey,
    connectedAt: Date.now(),
  };
  await chrome.storage.local.set({ [keyFor(provider)]: token });
}

export async function deleteToken(provider: Provider): Promise<void> {
  await chrome.storage.local.remove(keyFor(provider));
}

export async function isConnected(provider: Provider): Promise<boolean> {
  const token = await getToken(provider);
  return !!token?.accessToken;
}

export async function getAllStatuses(): Promise<ProviderStatus[]> {
  const providers: Provider[] = ["anthropic", "openai"];
  return Promise.all(
    providers.map(async (p) => {
      const token = await getToken(p);
      return {
        provider: p,
        connected: !!token?.accessToken,
        connectedAt: token?.connectedAt,
      };
    })
  );
}

/**
 * Fetches the list of available models for a provider using the stored key.
 */
export async function fetchModels(provider: Provider): Promise<ModelInfo[]> {
  const token = await getToken(provider);
  if (!token?.accessToken) throw new Error("No API key stored for this provider.");

  if (provider === "anthropic") {
    const res = await fetch("https://api.anthropic.com/v1/models?limit=100", {
      headers: {
        "x-api-key": token.accessToken,
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true",
      },
    });
    if (!res.ok) throw new Error(`Failed to fetch models (${res.status})`);
    const data = (await res.json()) as { data: { id: string; display_name?: string }[] };
    return data.data
      .filter((m) => m.id.startsWith("claude"))
      .map((m) => ({ id: m.id, displayName: m.display_name ?? m.id }));
  }

  if (provider === "openai") {
    const res = await fetch("https://api.openai.com/v1/models", {
      headers: { Authorization: `Bearer ${token.accessToken}` },
    });
    if (!res.ok) throw new Error(`Failed to fetch models (${res.status})`);
    const data = (await res.json()) as { data: { id: string }[] };
    return data.data
      .filter((m) => m.id.startsWith("gpt"))
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((m) => ({ id: m.id, displayName: m.id }));
  }

  return [];
}

/**
 * Validates an API key by making a cheap test call to the provider.
 * Returns null on success, or an error message string on failure.
 */
export async function validateApiKey(provider: Provider, apiKey: string): Promise<string | null> {
  try {
    if (provider === "anthropic") {
      // Use the models list endpoint — lightweight GET, no model name needed.
      const res = await fetch("https://api.anthropic.com/v1/models", {
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "anthropic-dangerous-direct-browser-access": "true",
        },
      });
      if (res.status === 401 || res.status === 403) {
        return "Invalid API key — check it and try again.";
      }
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        return `Anthropic returned ${res.status}${body ? ": " + body.slice(0, 120) : ""}`;
      }
      return null;
    }

    if (provider === "openai") {
      const res = await fetch("https://api.openai.com/v1/models", {
        headers: { Authorization: `Bearer ${apiKey}` },
      });
      if (res.status === 401 || res.status === 403) {
        return "Invalid API key — check it and try again.";
      }
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        return `OpenAI returned ${res.status}${body ? ": " + body.slice(0, 120) : ""}`;
      }
      return null;
    }

    return null;
  } catch (err) {
    return `Could not reach the API: ${(err as Error).message}`;
  }
}
