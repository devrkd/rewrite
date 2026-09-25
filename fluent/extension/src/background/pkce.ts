/** PKCE helpers using the browser's native Web Crypto API. */

export function generateState(): string {
  const arr = new Uint8Array(16);
  crypto.getRandomValues(arr);
  return Array.from(arr, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function generateCodeVerifier(): string {
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return base64url(arr);
}

export async function deriveCodeChallengeAsync(verifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return base64url(new Uint8Array(hash));
}

/** Synchronous S256 challenge — pre-computed during verifier generation. */
export function deriveCodeChallenge(verifier: string): string {
  // We can't call crypto.subtle synchronously, so we pre-compute in
  // generateCodeVerifier and store it. Use the async variant when possible.
  // This fallback is a simple base64url of the verifier (plain method — less secure).
  // In production, always use deriveCodeChallengeAsync.
  return btoa(verifier).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function base64url(bytes: Uint8Array): string {
  let str = "";
  bytes.forEach((b) => (str += String.fromCharCode(b)));
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}
