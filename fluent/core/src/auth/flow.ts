/**
 * OAuth 2.0 flow orchestrator.
 * Builds authorization URLs and handles token exchange.
 */
import type { Provider } from "../types.js";
import { getProviderConfig } from "./providers.js";
import { generateCodeVerifier, deriveCodeChallenge, generateState } from "./pkce.js";
import { saveToken } from "./store.js";

/** In-memory pending flow state — keyed by `state` param. */
interface PendingFlow {
  provider: Provider;
  codeVerifier: string;
  createdAt: number;
}

const pending = new Map<string, PendingFlow>();

/** Remove stale pending flows older than 10 minutes. */
function prunePending(): void {
  const cutoff = Date.now() - 10 * 60 * 1000;
  for (const [state, flow] of pending) {
    if (flow.createdAt < cutoff) pending.delete(state);
  }
}

// MARK: - Start flow

export interface StartFlowResult {
  /** The URL to open in the user's browser */
  authorizationUrl: string;
  /** Opaque state token — used to match the callback */
  state: string;
}

export function startFlow(provider: Provider): StartFlowResult {
  prunePending();

  const config = getProviderConfig(provider);
  const state = generateState();
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = deriveCodeChallenge(codeVerifier);

  pending.set(state, { provider, codeVerifier, createdAt: Date.now() });

  const params = new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: config.scopes.join(" "),
    state,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
  });

  return {
    authorizationUrl: `${config.authorizationUrl}?${params.toString()}`,
    state,
  };
}

// MARK: - Handle callback

export interface CallbackResult {
  provider: Provider;
  accountEmail?: string;
  accountName?: string;
}

export async function handleCallback(
  code: string,
  state: string
): Promise<CallbackResult> {
  const flow = pending.get(state);
  if (!flow) throw new Error("Unknown or expired OAuth state. Please start the connection flow again.");
  pending.delete(state);

  const config = getProviderConfig(flow.provider);

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: config.redirectUri,
    client_id: config.clientId,
    code_verifier: flow.codeVerifier,
  });

  const tokenRes = await fetch(config.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!tokenRes.ok) {
    const text = await tokenRes.text();
    throw new Error(`Token exchange failed (${tokenRes.status}): ${text}`);
  }

  const tokenData = (await tokenRes.json()) as {
    access_token: string;
    refresh_token?: string;
    expires_in?: number;
    token_type?: string;
  };

  let accountEmail: string | undefined;
  let accountName: string | undefined;

  // Fetch basic account info if the provider supports it
  if (config.accountInfoUrl) {
    try {
      const infoRes = await fetch(config.accountInfoUrl, {
        headers: { Authorization: `Bearer ${tokenData.access_token}` },
      });
      if (infoRes.ok) {
        const info = (await infoRes.json()) as { email?: string; name?: string };
        accountEmail = info.email;
        accountName = info.name;
      }
    } catch {
      // Non-fatal — account info is decorative only
    }
  }

  saveToken(flow.provider, {
    accessToken: tokenData.access_token,
    refreshToken: tokenData.refresh_token,
    expiresAt: tokenData.expires_in ? Date.now() + tokenData.expires_in * 1000 : undefined,
    accountEmail,
    accountName,
    connectedAt: Date.now(),
  });

  return { provider: flow.provider, accountEmail, accountName };
}
