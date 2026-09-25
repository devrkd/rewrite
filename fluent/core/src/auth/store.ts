/**
 * Persistent token store.
 * Saves to ~/.fluent/tokens.json with mode 0600 so only the owner can read it.
 * In a future iteration this should use the OS keychain (e.g. via `keytar`).
 */
import fs from "fs";
import path from "path";
import os from "os";
import type { Provider } from "../types.js";

export interface StoredToken {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number; // Unix ms
  /** Human-readable account info returned by the provider */
  accountEmail?: string;
  accountName?: string;
  connectedAt: number; // Unix ms
}

export type TokenStore = Partial<Record<Provider, StoredToken>>;

const FLUENT_DIR = path.join(os.homedir(), ".fluent");
const TOKEN_FILE = path.join(FLUENT_DIR, "tokens.json");

function ensureDir(): void {
  if (!fs.existsSync(FLUENT_DIR)) {
    fs.mkdirSync(FLUENT_DIR, { mode: 0o700, recursive: true });
  }
}

function read(): TokenStore {
  try {
    if (!fs.existsSync(TOKEN_FILE)) return {};
    const raw = fs.readFileSync(TOKEN_FILE, "utf8");
    return JSON.parse(raw) as TokenStore;
  } catch {
    return {};
  }
}

function write(store: TokenStore): void {
  ensureDir();
  fs.writeFileSync(TOKEN_FILE, JSON.stringify(store, null, 2), {
    encoding: "utf8",
    mode: 0o600,
  });
}

export function getToken(provider: Provider): StoredToken | null {
  return read()[provider] ?? null;
}

export function saveToken(provider: Provider, token: StoredToken): void {
  const store = read();
  store[provider] = token;
  write(store);
}

export function deleteToken(provider: Provider): void {
  const store = read();
  delete store[provider];
  write(store);
}

export function isConnected(provider: Provider): boolean {
  const token = getToken(provider);
  if (!token) return false;
  if (token.expiresAt && Date.now() > token.expiresAt) return false;
  return true;
}

export function getAllStatus(): Record<Provider, boolean> {
  return {
    anthropic: isConnected("anthropic"),
    openai: isConnected("openai"),
    gemini: isConnected("gemini"),
  };
}
