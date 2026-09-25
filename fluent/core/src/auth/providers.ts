/**
 * OAuth 2.0 provider configurations.
 *
 * Anthropic:
 *   Register your app at https://console.anthropic.com/settings/oauth-apps
 *   Redirect URI to register: http://localhost:7432/auth/anthropic/callback
 *
 * OpenAI:
 *   Register your app at https://platform.openai.com/settings/oauth
 *   Redirect URI to register: http://localhost:7432/auth/openai/callback
 */
import type { Provider } from "../types.js";

const PORT = process.env.PORT ?? "7432";

export interface OAuthProviderConfig {
  /** Displayed in UI */
  displayName: string;
  /** OAuth 2.0 authorization endpoint */
  authorizationUrl: string;
  /** OAuth 2.0 token endpoint */
  tokenUrl: string;
  /** OAuth 2.0 client_id — set via env var */
  clientId: string;
  /** Redirect URI registered with the provider */
  redirectUri: string;
  /** Scopes to request */
  scopes: string[];
  /** Whether to use PKCE (always true for native/public clients) */
  usePkce: boolean;
  /** Endpoint to fetch basic account info after connecting (optional) */
  accountInfoUrl?: string;
}

const CONFIGS: Record<Provider, OAuthProviderConfig> = {
  anthropic: {
    displayName: "Claude (Anthropic)",
    authorizationUrl: "https://claude.ai/oauth/authorize",
    tokenUrl: "https://api.anthropic.com/oauth/token",
    clientId: process.env.ANTHROPIC_CLIENT_ID ?? "",
    redirectUri: `http://localhost:${PORT}/auth/anthropic/callback`,
    scopes: ["org:create_api_key"],
    usePkce: true,
  },
  openai: {
    displayName: "ChatGPT (OpenAI)",
    authorizationUrl: "https://auth.openai.com/authorize",
    tokenUrl: "https://auth.openai.com/oauth/token",
    clientId: process.env.OPENAI_CLIENT_ID ?? "",
    redirectUri: `http://localhost:${PORT}/auth/openai/callback`,
    scopes: ["openid", "profile", "email", "offline_access"],
    usePkce: true,
  },
  gemini: {
    displayName: "Gemini (Google)",
    authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    clientId: process.env.GOOGLE_CLIENT_ID ?? "",
    redirectUri: `http://localhost:${PORT}/auth/gemini/callback`,
    scopes: [
      "https://www.googleapis.com/auth/generative-language.retriever",
      "openid",
      "email",
      "profile",
    ],
    usePkce: true,
    accountInfoUrl: "https://www.googleapis.com/oauth2/v3/userinfo",
  },
};

export function getProviderConfig(provider: Provider): OAuthProviderConfig {
  return CONFIGS[provider];
}
