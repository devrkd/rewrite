export type TriggerMode = "fixit" | "rewrite" | "formal" | "casual";
export type Provider = "anthropic" | "openai";

export interface DiffSegment {
  type: "equal" | "insert" | "delete";
  value: string;
}

export interface CorrectResult {
  original: string;
  corrected: string;
  diff: DiffSegment[];
}

// Messages between content script ↔ background worker
export type ExtMessage =
  | { type: "CORRECT"; text: string; mode: TriggerMode }
  | { type: "GET_AUTH_STATUS" }
  | { type: "SAVE_API_KEY"; provider: Provider; apiKey: string }
  | { type: "DISCONNECT"; provider: Provider }
  | { type: "GET_MODELS"; provider: Provider };

export type ExtResponse =
  | { type: "CORRECT_OK"; result: CorrectResult }
  | { type: "CORRECT_ERR"; error: string; notConnected?: boolean }
  | { type: "AUTH_STATUS"; statuses: ProviderStatus[] }
  | { type: "SAVE_API_KEY_OK"; provider: Provider }
  | { type: "SAVE_API_KEY_ERR"; provider: Provider; error: string }
  | { type: "DISCONNECT_OK"; provider: Provider }
  | { type: "MODELS_OK"; provider: Provider; models: ModelInfo[] }
  | { type: "MODELS_ERR"; provider: Provider; error: string };

export interface ModelInfo {
  id: string;
  displayName: string;
}

export interface ProviderStatus {
  provider: Provider;
  connected: boolean;
  connectedAt?: number;
}

export interface StoredToken {
  accessToken: string;         // the API key
  refreshToken?: string;
  expiresAt?: number;
  email?: string;
  name?: string;
  connectedAt: number;
}
